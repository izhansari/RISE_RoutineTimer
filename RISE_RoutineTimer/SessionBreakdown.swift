//
//  SessionBreakdown.swift
//  RISE_RoutineTimer
//
//  How each step of a finished run went, in words the summary can draw.
//
//  The one idea here: a step that barely happened is not a quick step. The
//  run that prompted this reported "17:28 ahead" — 17:08 of it was three
//  steps checked off in under 35 seconds, and the other twelve came in 20
//  seconds under. So a step checked off before a quarter of its plan (or
//  skipped) is classed apart and kept out of the pace number.
//
//  Pure and tested.
//

import Foundation

nonisolated enum StepOutcome: Equatable {
    case over
    case under
    case onPlan
    /// Checked off before a quarter of its plan had passed.
    case cutShort
    case skipped
    /// Advanced by the engine the moment its time was up, so it cannot deviate.
    case auto

    /// Within this many seconds of plan counts as on plan.
    static let onPlanToleranceSeconds = 3
    /// Under this share of the plan, a step "barely happened".
    static let cutShortShare = 0.25

    init(_ step: StepResult) {
        if step.wasSkipped {
            self = .skipped
        } else if step.autoAdvanced, abs(step.deltaSeconds) <= Self.onPlanToleranceSeconds {
            // An auto step ends the moment its time is up, so it cannot
            // deviate. If the record says it did anyway, trust the times —
            // otherwise the row draws an on-plan pin beside a −41%.
            self = .auto
        } else if step.plannedSeconds > 0,
                  Double(step.actualSeconds) < Double(step.plannedSeconds) * Self.cutShortShare {
            self = .cutShort
        } else if step.deltaSeconds > Self.onPlanToleranceSeconds {
            self = .over
        } else if step.deltaSeconds < -Self.onPlanToleranceSeconds {
            self = .under
        } else {
            self = .onPlan
        }
    }

    /// Cut short and skipped steps say nothing about pace.
    var barelyHappened: Bool { self == .cutShort || self == .skipped }

    /// Timed normally: over, under or on plan. These are the only runs that
    /// say how long a step takes — an auto step always takes its plan, and a
    /// cut-short or skipped one barely happened. `StepReport` and
    /// `RoutineStats` both count by this, so the step history page, the stats
    /// sheet and the suggestions cannot disagree about the same step.
    var isTimed: Bool { self == .over || self == .under || self == .onPlan }
}

extension StepResult {
    nonisolated var outcome: StepOutcome { StepOutcome(self) }

    /// See `StepOutcome.isTimed`.
    nonisolated var isTimed: Bool { outcome.isTimed }

    /// Time over or under as a share of the step's own plan: +0.2 is 20% over.
    nonisolated var shareOfPlan: Double {
        guard plannedSeconds > 0 else { return 0 }
        return Double(deltaSeconds) / Double(plannedSeconds)
    }
}

nonisolated struct SessionBreakdown: Equatable {
    enum Row: Equatable, Identifiable {
        case step(index: Int, result: StepResult, outcome: StepOutcome)
        /// Two or more auto steps in a row. They cannot deviate, so they do not
        /// need a row each to say so.
        case autoRun(firstIndex: Int, results: [StepResult])

        /// The position of the row's first step in the run — stable, unique.
        var id: Int {
            switch self {
            case .step(let index, _, _): return index
            case .autoRun(let firstIndex, _): return firstIndex
            }
        }
    }

    static let minimumAutoRun = 2

    let rows: [Row]
    /// Steps that tell you something about pace: everything but cut short and skipped.
    let pacedStepCount: Int
    let pacedDeltaSeconds: Int
    let barelyHappenedCount: Int
    let barelyHappenedDeltaSeconds: Int

    init(steps: [StepResult]) {
        var rows: [Row] = []
        var i = 0
        while i < steps.count {
            let outcome = steps[i].outcome
            guard outcome == .auto else {
                rows.append(.step(index: i, result: steps[i], outcome: outcome))
                i += 1
                continue
            }
            var end = i
            while end < steps.count, steps[end].outcome == .auto { end += 1 }
            if end - i >= Self.minimumAutoRun {
                rows.append(.autoRun(firstIndex: i, results: Array(steps[i..<end])))
            } else {
                for k in i..<end {
                    rows.append(.step(index: k, result: steps[k], outcome: .auto))
                }
            }
            i = end
        }
        self.rows = rows

        let paced = steps.filter { !$0.outcome.barelyHappened }
        let barely = steps.filter { $0.outcome.barelyHappened }
        pacedStepCount = paced.count
        pacedDeltaSeconds = paced.reduce(0) { $0 + $1.deltaSeconds }
        barelyHappenedCount = barely.count
        barelyHappenedDeltaSeconds = barely.reduce(0) { $0 + $1.deltaSeconds }
    }
}

// MARK: - Correcting a past run

extension SessionResult {
    /// The same run with one step's time corrected — for the morning you forgot
    /// to tap done and the last step "ran" for two hours.
    ///
    /// Everything downstream of that time moves with it: the run's active time
    /// changes by the difference, and so does its end, so the start–end range,
    /// the Today tab's routine end and every average read the corrected run.
    /// The start never moves — it was recorded correctly. A step fixed by hand
    /// is no longer "auto-advanced", since its time is no longer the plan's.
    nonisolated func correcting(stepAt index: Int, toSeconds seconds: Int) -> SessionResult {
        guard steps.indices.contains(index) else { return self }
        let newSeconds = max(0, seconds)
        let delta = newSeconds - steps[index].actualSeconds
        guard delta != 0 else { return self }

        var corrected = self
        corrected.steps[index].actualSeconds = newSeconds
        corrected.steps[index].autoAdvanced = false
        corrected.activeSeconds = max(0, activeSeconds + delta)
        corrected.endedAt = max(startedAt, endedAt.addingTimeInterval(TimeInterval(delta)))
        return corrected
    }
}
