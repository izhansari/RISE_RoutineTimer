//
//  MorningMetrics.swift
//  RISE_RoutineTimer
//
//  The accountability math, ported from the MorningCheckin web app's
//  `src/utils/metrics.js` so the two apps report the same numbers.
//
//  Three timestamps a day, measured against a target wake time:
//
//      target ───► wake ───► routine start ───► routine end
//               snooze     activation          duration
//
//  * Snooze     — wake minus target. Negative is early.
//  * Activation — how long from opening your eyes to actually starting.
//  * Duration   — the routine itself, which the engine already measures.
//
//  Everything here is pure and nonisolated so it can be unit tested against
//  synthetic dates, like the rest of the math in this project.
//

import Foundation

// MARK: - Settings

/// User targets and budgets. Mirrors the web app's `settings` table.
nonisolated struct MorningSettings: Equatable {
    static let targetWakeKey = "morningTargetWakeMinutes"
    static let snoozeBudgetKey = "morningSnoozeBudgetMinutes"
    static let activationBudgetKey = "morningActivationBudgetMinutes"

    /// Minutes after midnight.
    var targetWakeMinutes: Int = 6 * 60 + 30
    /// Weekly allowance, in minutes, for oversleeping past the target.
    var snoozeBudgetMinutes: Int = 60
    /// Weekly allowance, in minutes, for time between waking and starting.
    var activationBudgetMinutes: Int = 60

    static let defaultTargetWakeMinutes = 6 * 60 + 30
    static let defaultSnoozeBudget = 60
    static let defaultActivationBudget = 60

    /// The target as a clock time on the same day as `date`.
    func targetWake(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(TimeInterval(targetWakeMinutes * 60))
    }
}

// MARK: - One morning

/// A single day, joined from the wake log and the recorded routine session.
nonisolated struct MorningRecord: Equatable, Identifiable {
    /// Start of the local day this record belongs to.
    var day: Date
    var wakeAt: Date?
    var routineStartAt: Date?
    var routineEndAt: Date?
    var completedRoutine: Bool = false

    var id: Date { day }

    /// True once there is anything at all logged for the day.
    var hasAnything: Bool { wakeAt != nil || routineStartAt != nil }

    /// All three timestamps present — the only records the rolling baselines use.
    var isComplete: Bool {
        wakeAt != nil && routineStartAt != nil && routineEndAt != nil
    }

    /// Minutes past the target wake time. Negative means up early.
    func snoozeMinutes(settings: MorningSettings, calendar: Calendar = .current) -> Int? {
        guard let wakeAt else { return nil }
        let target = settings.targetWake(on: wakeAt, calendar: calendar)
        return Int((wakeAt.timeIntervalSince(target) / 60).rounded())
    }

    /// Minutes between waking and starting the routine. Nil when the routine
    /// somehow started before the logged wake time — that is a bad wake entry
    /// to be corrected, not a negative activation.
    var activationMinutes: Int? {
        guard let wakeAt, let routineStartAt, routineStartAt >= wakeAt else { return nil }
        return Int((routineStartAt.timeIntervalSince(wakeAt) / 60).rounded())
    }

    /// Minutes the routine itself took.
    var durationMinutes: Int? {
        guard let routineStartAt, let routineEndAt else { return nil }
        return Int((routineEndAt.timeIntervalSince(routineStartAt) / 60).rounded())
    }

    /// Wake time expressed as minutes after midnight, for the consistency spread.
    func wakeMinutesAfterMidnight(calendar: Calendar = .current) -> Int? {
        guard let wakeAt else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: wakeAt)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return hour * 60 + minute
    }
}

// MARK: - Metrics over many mornings

nonisolated struct MorningMetrics {
    /// Newest first.
    let records: [MorningRecord]
    let settings: MorningSettings
    var calendar: Calendar = .current

    init(records: [MorningRecord], settings: MorningSettings, calendar: Calendar = .current) {
        self.records = records.sorted { $0.day > $1.day }
        self.settings = settings
        self.calendar = calendar
    }

    /// The three metrics, as one type so the UI can loop over them.
    enum Metric: String, CaseIterable, Identifiable {
        case snooze, activation, duration

        var id: String { rawValue }

        var title: String {
            switch self {
            case .snooze:     return "Snooze"
            case .activation: return "Activation"
            case .duration:   return "Routine"
            }
        }

        /// True when a *smaller* number is a better morning. All three, as it
        /// happens — but stating it keeps the comparison code honest.
        var lowerIsBetter: Bool { true }
    }

    func value(_ metric: Metric, for record: MorningRecord) -> Int? {
        switch metric {
        case .snooze:     return record.snoozeMinutes(settings: settings, calendar: calendar)
        case .activation: return record.activationMinutes
        case .duration:   return record.durationMinutes
        }
    }

    var latest: MorningRecord? { records.first { $0.isComplete } }

    func record(on date: Date) -> MorningRecord? {
        let day = calendar.startOfDay(for: date)
        return records.first { $0.day == day }
    }

    // MARK: Baselines

    /// Mean of `metric` over records from the last `days` days, ignoring days
    /// that don't have the data. Nil when nothing qualifies.
    func rollingAverage(_ metric: Metric, days: Int, now: Date = Date(), excluding excludedDay: Date? = nil) -> Int? {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else { return nil }
        let excluded = excludedDay.map { calendar.startOfDay(for: $0) }
        let values = records
            .filter { $0.isComplete && $0.day >= cutoff && $0.day != excluded }
            .compactMap { value(metric, for: $0) }
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    /// The value on the most recent complete day before `now`.
    func previousValue(_ metric: Metric, now: Date = Date()) -> Int? {
        let today = calendar.startOfDay(for: now)
        return records.first { $0.isComplete && $0.day < today }.flatMap { value(metric, for: $0) }
    }

    /// Population standard deviation of wake times over the last `days` days,
    /// in minutes. This is the "±14 min" consistency figure — a different
    /// signal from the average, and the one that actually tracks discipline.
    func wakeConsistencyMinutes(days: Int, now: Date = Date()) -> Int? {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else { return nil }
        let times = records
            .filter { $0.day >= cutoff }
            .compactMap { $0.wakeMinutesAfterMidnight(calendar: calendar) }
            .map(Double.init)
        guard times.count >= 2 else { return nil }
        let mean = times.reduce(0, +) / Double(times.count)
        let variance = times.reduce(0) { $0 + pow($1 - mean, 2) } / Double(times.count)
        return Int(variance.squareRoot().rounded())
    }

    /// Average wake time as minutes after midnight, over the last `days` days.
    func averageWakeMinutes(days: Int, now: Date = Date()) -> Int? {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else { return nil }
        let times = records
            .filter { $0.day >= cutoff }
            .compactMap { $0.wakeMinutesAfterMidnight(calendar: calendar) }
        guard !times.isEmpty else { return nil }
        return Int((Double(times.reduce(0, +)) / Double(times.count)).rounded())
    }

    // MARK: Budgets

    /// Minutes of `metric` spent so far this week. Only overruns count — being
    /// up early doesn't earn credit to spend on a later lie-in.
    func weeklyBudgetUsed(_ metric: Metric, now: Date = Date()) -> Int {
        let start = startOfWeek(containing: now)
        return records
            .filter { $0.day >= start }
            .compactMap { value(metric, for: $0) }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    func budget(for metric: Metric) -> Int? {
        switch metric {
        case .snooze:     return settings.snoozeBudgetMinutes
        case .activation: return settings.activationBudgetMinutes
        case .duration:   return nil
        }
    }

    func startOfWeek(containing date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let offset = weekday - calendar.firstWeekday
        let normalized = offset < 0 ? offset + 7 : offset
        return calendar.date(byAdding: .day, value: -normalized, to: start) ?? start
    }

    // MARK: Missed days

    nonisolated struct MissedDays: Equatable {
        var week = 0
        var month = 0
        var allTime = 0
    }

    /// Days since the first logged morning with nothing recorded at all.
    /// Today is never counted — the morning may not be over yet.
    func missedDays(now: Date = Date()) -> MissedDays {
        let logged = Set(records.filter(\.hasAnything).map(\.day))
        guard let first = logged.min() else { return MissedDays() }

        let today = calendar.startOfDay(for: now)
        let weekStart = startOfWeek(containing: now)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today

        var result = MissedDays()
        var cursor = first
        while cursor < today {
            if !logged.contains(cursor) {
                result.allTime += 1
                if cursor >= weekStart { result.week += 1 }
                if cursor >= monthStart { result.month += 1 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Consecutive days ending today (or yesterday) with a completed routine.
    func currentStreak(now: Date = Date()) -> Int {
        let done = Set(records.filter(\.completedRoutine).map(\.day))
        guard !done.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        // A routine not yet run today shouldn't break a streak mid-morning.
        if !done.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while done.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    // MARK: Insights

    /// Plain sentences for the insight card, best first.
    func insights(now: Date = Date()) -> [String] {
        let complete = records.filter(\.isComplete)
        guard !complete.isEmpty else { return ["Keep logging — insights build over time."] }

        var lines: [String] = []
        lines.append("You've logged \(complete.count) morning\(complete.count == 1 ? "" : "s") total.")

        var latencyStreak = 0
        for record in complete {
            guard let latency = record.activationMinutes, latency < 10 else { break }
            latencyStreak += 1
        }
        if latencyStreak >= 2 {
            lines.append("Activation under 10 min — \(latencyStreak) days in a row.")
        }

        let last7 = Array(complete.prefix(7))
        let prior7 = Array(complete.dropFirst(7).prefix(7))
        if last7.count >= 3, prior7.count >= 3 {
            let mean: ([MorningRecord]) -> Double = { group in
                let values = group.compactMap { $0.snoozeMinutes(settings: settings, calendar: calendar) }
                guard !values.isEmpty else { return 0 }
                return Double(values.reduce(0, +)) / Double(values.count)
            }
            let improvement = Int((mean(prior7) - mean(last7)).rounded())
            if improvement > 0 {
                lines.append("Waking \(improvement) min earlier than the week before.")
            }
        }

        let onTime = last7.filter { ($0.snoozeMinutes(settings: settings, calendar: calendar) ?? 1) <= 0 }.count
        if last7.count >= 5, onTime > 0 {
            lines.append("\(onTime) of your last \(last7.count) mornings started on time.")
        }

        if let spread = wakeConsistencyMinutes(days: 7, now: now), spread <= 15 {
            lines.append("Solid consistency this week — ±\(spread) min spread in wake time.")
        }

        let missed = missedDays(now: now)
        if missed.week > 0 {
            lines.append("\(missed.week) missed day\(missed.week == 1 ? "" : "s") this week.")
        }

        return lines
    }
}
