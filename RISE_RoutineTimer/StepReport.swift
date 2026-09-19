//
//  StepReport.swift
//  RISE_RoutineTimer
//
//  One step's record over time: what the step history page is drawn from.
//
//  The questions it answers, roughly in the order people ask them:
//  how long does this actually take me (typical, and the usual window)?
//  is my plan right? am I getting faster or slower? what were my best and
//  worst runs? do I actually do it, or cut it short? where does it sit in
//  the morning, and how much of the routine does it eat?
//
//  "Typical" is a median, not a mean: one morning spent looking for a sock
//  shouldn't move it. Only runs that were timed normally count toward it —
//  auto steps always take exactly their plan, and cut-short or skipped runs
//  barely happened (see `StepOutcome`).
//
//  Pure and tested.
//

import Foundation

nonisolated struct StepReport: Equatable {
    nonisolated struct Run: Equatable, Identifiable {
        let sessionStart: Date
        let result: StepResult
        let outcome: StepOutcome
        /// How far into that morning's routine the step began: the time taken
        /// by every step before it in the same run.
        let startOffsetSeconds: Int
        /// The share of that run's active time this step took.
        let shareOfRoutine: Double

        var id: Date { sessionStart }
    }

    /// Runs kept, most recent. Enough to see a trend; not so many that a
    /// routine from months ago decides what "typical" means today.
    static let window = 30
    /// Recent runs compared against the same number just before them.
    static let trendWindow = 5
    static let minimumTrendRuns = 3

    let plannedSeconds: Int
    /// Oldest first.
    let runs: [Run]

    /// - Parameter plannedSeconds: the step's plan *now*, which is what "vs
    ///   plan" should mean on the page. Each run's result keeps the plan it
    ///   had at the time.
    init(stepID: UUID, plannedSeconds: Int, sessions: [SessionResult]) {
        self.plannedSeconds = plannedSeconds

        var runs: [Run] = []
        for session in sessions.filter(\.completed).sorted(by: { $0.startedAt < $1.startedAt }) {
            var offset = 0
            for result in session.steps {
                if result.stepID == stepID {
                    let share = session.activeSeconds > 0
                        ? Double(result.actualSeconds) / Double(session.activeSeconds)
                        : 0
                    runs.append(Run(
                        sessionStart: session.startedAt,
                        result: result,
                        outcome: result.outcome,
                        startOffsetSeconds: offset,
                        shareOfRoutine: share
                    ))
                    break
                }
                offset += result.actualSeconds
            }
        }
        self.runs = Array(runs.suffix(Self.window))
    }

    // MARK: - Timing

    /// Runs that were timed normally: over, under or on plan.
    var timed: [Run] {
        runs.filter { $0.outcome == .over || $0.outcome == .under || $0.outcome == .onPlan }
    }

    private var timedSeconds: [Int] { timed.map(\.result.actualSeconds) }

    /// Every run was auto-advanced, so there is nothing to time.
    var isAutoOnly: Bool { !runs.isEmpty && runs.allSatisfy { $0.outcome == .auto } }

    /// The median of the timed runs, once there are two.
    var typicalSeconds: Int? {
        let t = timedSeconds
        guard t.count >= 2 else { return nil }
        return Self.percentile(t, 0.5)
    }

    /// The middle half of the timed runs, once there are four.
    var usualRange: ClosedRange<Int>? {
        let t = timedSeconds
        guard t.count >= 4 else { return nil }
        return Self.percentile(t, 0.25)...Self.percentile(t, 0.75)
    }

    var best: Run? { timed.min { $0.result.actualSeconds < $1.result.actualSeconds } }
    var slowest: Run? { timed.max { $0.result.actualSeconds < $1.result.actualSeconds } }

    /// Median of the most recent runs minus the median of the ones just
    /// before them. Negative is faster. Nil until there are at least three
    /// timed runs on each side.
    var trendSeconds: Int? {
        let t = timedSeconds
        let k = min(Self.trendWindow, t.count / 2)
        guard k >= Self.minimumTrendRuns else { return nil }
        let recent = Array(t.suffix(k))
        let before = Array(t.dropLast(k).suffix(k))
        return Self.percentile(recent, 0.5) - Self.percentile(before, 0.5)
    }

    // MARK: - Counts

    func count(_ outcome: StepOutcome) -> Int {
        runs.filter { $0.outcome == outcome }.count
    }

    /// Runs where the step genuinely happened — not cut short, not skipped.
    var finishedCount: Int { runs.filter { !$0.outcome.barelyHappened }.count }

    // MARK: - Place in the morning

    var typicalStartOffsetSeconds: Int? {
        guard !runs.isEmpty else { return nil }
        return Self.percentile(runs.map(\.startOffsetSeconds), 0.5)
    }

    var averageShareOfRoutine: Double? {
        let shares = runs.filter { !$0.outcome.barelyHappened }.map(\.shareOfRoutine)
        guard !shares.isEmpty else { return nil }
        return shares.reduce(0, +) / Double(shares.count)
    }

    // MARK: - Maths

    /// Linear-interpolated percentile of whole seconds, rounded.
    static func percentile(_ values: [Int], _ p: Double) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let position = min(1, max(0, p)) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let fraction = position - Double(lower)
        return Int((Double(sorted[lower]) + Double(sorted[upper] - sorted[lower]) * fraction).rounded())
    }
}
