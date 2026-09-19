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

// MARK: - Where the time went

/// A finished run as shares of the time it took: what the summary's ring is
/// drawn from, and how a touch on the ring finds its step.
///
/// Shares are of the *steps'* time, not the session's active time. The two are
/// equal for a finished run, but a run ended early also counts the part of
/// the step it was abandoned on, which has no result and so no slice — and a
/// ring whose slices stop at 93% reads as a drawing bug.
nonisolated struct RunComposition: Equatable {
    nonisolated struct Slice: Equatable, Identifiable {
        /// Position in the run.
        let index: Int
        let result: StepResult
        let outcome: StepOutcome
        /// How far into the run this step began, by step time (pauses excluded).
        let startSeconds: Int
        /// This step's share of the run's step time, 0…1.
        let share: Double

        var id: Int { index }
        var endSeconds: Int { startSeconds + max(0, result.actualSeconds) }
    }

    let slices: [Slice]
    let totalSeconds: Int

    init(steps: [StepResult]) {
        let total = steps.reduce(0) { $0 + max(0, $1.actualSeconds) }
        var offset = 0
        var slices: [Slice] = []
        for (index, step) in steps.enumerated() {
            let seconds = max(0, step.actualSeconds)
            slices.append(Slice(
                index: index,
                result: step,
                outcome: step.outcome,
                startSeconds: offset,
                share: total > 0 ? Double(seconds) / Double(total) : 0
            ))
            offset += seconds
        }
        self.slices = slices
        totalSeconds = total
    }

    /// The step under a point `seconds` into the run. A boundary belongs to
    /// the step that starts there, a step that took no time can never be
    /// under a finger, and a point off either end clamps to the nearest step
    /// that has any width.
    func index(atSeconds seconds: Double) -> Int? {
        let drawn = slices.filter { $0.result.actualSeconds > 0 }
        guard let first = drawn.first, let last = drawn.last else { return nil }
        if seconds < Double(first.startSeconds) { return first.index }
        return drawn.first { seconds < Double($0.endSeconds) }?.index ?? last.index
    }

    /// The step under a tap on the ring, which is drawn centred in `size`,
    /// clockwise from twelve, with a hole `innerRatio` of its radius wide.
    /// Nil in the hole and outside the ring: the hole holds the readout, and
    /// a tap there is not a tap on a step.
    ///
    /// Done by hand because Swift Charts' own selection waits for a short
    /// press when the chart is inside a scroll view — that is how it tells a
    /// touch from a scroll — so a plain tap, the obvious thing to do to a
    /// slice, did nothing at all.
    func index(at point: CGPoint, inRingOf size: CGSize, innerRatio: Double) -> Int? {
        let radius = Double(min(size.width, size.height)) / 2
        guard radius > 0, totalSeconds > 0 else { return nil }
        let dx = Double(point.x - size.width / 2)
        let dy = Double(point.y - size.height / 2)
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= radius * innerRatio, distance <= radius else { return nil }

        // Clockwise from twelve: straight up is 0, three o'clock a quarter.
        var turn = atan2(dx, -dy) / (2 * Double.pi)
        if turn < 0 { turn += 1 }
        return index(atSeconds: turn * Double(totalSeconds))
    }

    /// The step that took the most time — where the ring opens. The earlier
    /// one on a tie.
    var largestIndex: Int? {
        var best: Slice?
        for slice in slices where slice.result.actualSeconds > (best?.result.actualSeconds ?? 0) {
            best = slice
        }
        return best?.index
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
