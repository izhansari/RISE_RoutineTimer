//
//  RoutineStats.swift
//  RISE_RoutineTimer
//
//  Pure calculations over past sessions: averages, streaks, and suggested
//  step durations. Kept free of SwiftData so it is easy to unit test.
//

import Foundation

nonisolated struct StepSuggestion: Equatable, Identifiable {
    var stepID: UUID
    var title: String
    var plannedSeconds: Int
    var averageActualSeconds: Int
    var suggestedSeconds: Int
    var sampleCount: Int

    var id: UUID { stepID }
    var isShorter: Bool { suggestedSeconds < plannedSeconds }
}

nonisolated struct RoutineStats {
    /// Completed sessions, newest first.
    let completed: [SessionResult]
    let calendar: Calendar

    init(sessions: [SessionResult], calendar: Calendar = .current) {
        completed = sessions.filter(\.completed).sorted { $0.startedAt > $1.startedAt }
        self.calendar = calendar
    }

    var count: Int { completed.count }

    var averageActiveSeconds: Int? {
        guard !completed.isEmpty else { return nil }
        return completed.reduce(0) { $0 + $1.activeSeconds } / completed.count
    }

    var bestActiveSeconds: Int? {
        completed.map(\.activeSeconds).min()
    }

    var latest: SessionResult? { completed.first }

    /// Average clock time the routine was started, as seconds after midnight.
    var averageStartSecondsSinceMidnight: Int? {
        guard !completed.isEmpty else { return nil }
        let total = completed.reduce(0) { $0 + secondsSinceMidnight(of: $1.startedAt) }
        return total / completed.count
    }

    /// Average of the last `window` sessions versus the ones before them.
    /// Negative means recent sessions are faster.
    func recentTrendSeconds(window: Int = 5) -> Int? {
        guard completed.count >= window * 2 else { return nil }
        let recent = completed.prefix(window).reduce(0) { $0 + $1.activeSeconds } / window
        let earlier = completed.dropFirst(window).prefix(window).reduce(0) { $0 + $1.activeSeconds } / window
        return recent - earlier
    }

    /// Consecutive days, ending today or yesterday, with a completed session.
    func currentStreak(today: Date = Date()) -> Int {
        let days = Set(completed.map { calendar.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    func secondsSinceMidnight(of date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    // MARK: - Per-step averages

    /// Typical actual time for one step over recent sessions, on the same
    /// evidence rules as `suggestions`: only manual completions count, since
    /// an auto-advanced step always "takes" exactly its planned time.
    func averageActual(forStepID id: UUID) -> StepAverage? {
        let recent = completed.prefix(Self.suggestionSessionWindow)
        let samples = recent.flatMap { session in
            session.steps.filter { $0.stepID == id && !$0.autoAdvanced && !$0.wasSkipped }.map(\.actualSeconds)
        }
        guard samples.count >= 2 else { return nil }
        return StepAverage(averageSeconds: samples.reduce(0, +) / samples.count, sampleCount: samples.count)
    }

    /// Everything the step-stats sheet shows for one step, over the same
    /// recent window as `suggestions`. Averages use manual completions only
    /// (an auto-advanced step always "takes" its planned time); the skip and
    /// auto-advance counts cover every appearance.
    func history(forStepID id: UUID) -> StepHistory {
        let recent = completed.prefix(Self.suggestionSessionWindow)
        let appearances = recent.flatMap { session in
            session.steps.filter { $0.stepID == id }
        }
        let manual = appearances.filter { !$0.autoAdvanced && !$0.wasSkipped }.map(\.actualSeconds)
        return StepHistory(
            appearances: appearances.count,
            manualSamples: manual,
            skipped: appearances.filter(\.wasSkipped).count,
            autoAdvanced: appearances.filter { $0.autoAdvanced && !$0.wasSkipped }.count
        )
    }

    // MARK: - Suggestions

    static let suggestionMinimumSamples = 3
    static let suggestionSessionWindow = 10

    /// Steps whose typical actual time differs enough from the plan to be
    /// worth adjusting. Only manually completed steps count as evidence,
    /// since an auto-advanced step always "takes" exactly its planned time.
    func suggestions(for steps: [RunStep]) -> [StepSuggestion] {
        let recent = completed.prefix(Self.suggestionSessionWindow)

        return steps.compactMap { step in
            let samples = recent.flatMap { session in
                session.steps.filter { $0.stepID == step.id && !$0.autoAdvanced && !$0.wasSkipped }.map(\.actualSeconds)
            }
            guard samples.count >= Self.suggestionMinimumSamples else { return nil }

            let average = samples.reduce(0, +) / samples.count
            let difference = average - step.durationSeconds
            let threshold = max(30, step.durationSeconds * 15 / 100)
            guard abs(difference) >= threshold else { return nil }

            let suggested = Self.roundedDuration(average)
            guard suggested != step.durationSeconds else { return nil }

            return StepSuggestion(
                stepID: step.id,
                title: step.title,
                plannedSeconds: step.durationSeconds,
                averageActualSeconds: average,
                suggestedSeconds: suggested,
                sampleCount: samples.count
            )
        }
    }

    /// Rounds to a duration a person would actually pick: 15 s under 2 min,
    /// 30 s under 10 min, whole minutes above.
    static func roundedDuration(_ seconds: Int) -> Int {
        let unit = seconds < 120 ? 15 : seconds < 600 ? 30 : 60
        let rounded = Int((Double(seconds) / Double(unit)).rounded()) * unit
        return max(RoutineStep.minimumDurationSeconds, rounded)
    }
}

nonisolated struct StepAverage: Equatable {
    var averageSeconds: Int
    var sampleCount: Int
}

/// One step's recent record. `manualSamples` are newest first.
nonisolated struct StepHistory: Equatable {
    var appearances: Int
    var manualSamples: [Int]
    var skipped: Int
    var autoAdvanced: Int

    var averageSeconds: Int? {
        guard manualSamples.count >= 2 else { return nil }
        return manualSamples.reduce(0, +) / manualSamples.count
    }
    var bestSeconds: Int? { manualSamples.min() }
    var lastSeconds: Int? { manualSamples.first }
    var hasEvidence: Bool { appearances > 0 }
}
