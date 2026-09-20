//
//  MorningColumns.swift
//  RISE_RoutineTimer
//
//  One morning as an upright mark, and the clock it is drawn against. The
//  same mark is used on both tabs: History stands fourteen of them side by
//  side, Today puts the morning that is still happening at the end of the
//  week's and lets it grow.
//
//      ┊  dotted    goal → woke          the snooze
//      ━  cap       woke
//      │  whisker   woke → started       time to start
//      █  box       started → + routine  time spent doing it
//      ░  tail      … → really ended     a pause, when there was one
//
//  The clock runs *down* the page, so earlier is higher and a cap above the
//  goal line is a morning you were up early.
//
//  This replaced two things. History had three separate 30-day charts —
//  snooze, activation, routine length — that each answered "is this number
//  going up?" and between them could not answer "what goes with what?",
//  because the three never shared a day. Today had a horizontal timeline of
//  coloured dots, where the two moments that matter (woke, started) landed
//  on top of each other and the durations, which are the story, were left to
//  three tiles underneath.
//
//  Pure and tested; the drawing is `MorningColumnsView`.
//

import Foundation

/// One day's mark, in minutes since the start of that day.
nonisolated struct MorningColumn: Equatable, Identifiable {
    let day: Date
    /// The wake goal this morning was held to. Per-column rather than
    /// per-chart, so the goal line *steps* on the day the goal moved instead
    /// of redrawing the whole history at today's standard — which is the
    /// point of the app, and the one thing a straight line could not show.
    var goal: Int
    var wake: Int?
    var start: Int?
    /// Where the routine's box ends: its start plus the time spent *doing*
    /// it, which is what "routine length" means everywhere else in the app.
    var end: Int?
    /// When the run really ended on the clock, if pauses pushed that past
    /// `end`. Drawn as a faint tail so the box stays honest about the
    /// routine and the column stays honest about the morning.
    var pausedUntil: Int?
    /// The session this column's routine came from — its start, which is a
    /// session's identity — so History can open the run.
    var sessionStart: Date?

    var id: Date { day }
    var hasAnything: Bool { wake != nil || start != nil }

    /// Minutes between waking and starting. Nil when either is missing, or
    /// when the wake was logged after the start (a bad wake entry, the same
    /// rule `MorningRecord.activationMinutes` applies).
    var lag: Int? {
        guard let wake, let start, start >= wake else { return nil }
        return start - wake
    }

    var routineMinutes: Int? {
        guard let start, let end else { return nil }
        return max(0, end - start)
    }

    /// A pause shorter than this is rounding, not a tail worth drawing.
    static let minimumTail = 2

    init(day: Date, goal: Int, wake: Int? = nil, start: Int? = nil, end: Int? = nil, pausedUntil: Int? = nil, sessionStart: Date? = nil) {
        self.day = day
        self.goal = goal
        self.wake = wake
        self.start = start
        self.end = end
        self.pausedUntil = pausedUntil
        self.sessionStart = sessionStart
    }

    init(record: MorningRecord, currentGoal: Int) {
        day = record.day
        goal = record.goalMinutes ?? currentGoal
        wake = record.wakeAt.map { Self.minutes($0, into: record.day) }
        sessionStart = record.routineStartAt

        guard let startedAt = record.routineStartAt else { return }
        let start = Self.minutes(startedAt, into: record.day)
        self.start = start

        guard let endedAt = record.routineEndAt else { return }
        let onTheClock = Self.minutes(endedAt, into: record.day)
        let active = record.routineActiveSeconds.map { start + Int((Double($0) / 60).rounded()) } ?? onTheClock
        // Active time cannot outrun the clock; a correction can make it try.
        let end = min(active, max(start, onTheClock))
        self.end = end
        pausedUntil = onTheClock - end >= Self.minimumTail ? onTheClock : nil
    }

    /// Minutes since the start of `day`, rather than the clock's own
    /// minutes-after-midnight: a run that crosses midnight keeps going down
    /// its column instead of wrapping round to the top.
    static func minutes(_ date: Date, into day: Date) -> Int {
        Int((date.timeIntervalSince(day) / 60).rounded())
    }

    /// `days` consecutive columns ending on `lastDay`, oldest first, with an
    /// empty column for every day nothing was logged — a missed day is a gap
    /// you can see, not a counter you have to read.
    static func window(
        records: [MorningRecord],
        endingOn lastDay: Date,
        days: Int,
        currentGoal: Int,
        calendar: Calendar = .current
    ) -> [MorningColumn] {
        let last = calendar.startOfDay(for: lastDay)
        let byDay = Dictionary(records.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { first, _ in first })

        var columns: [MorningColumn] = (0..<max(0, days)).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: last) else { return nil }
            return byDay[day].map { MorningColumn(record: $0, currentGoal: currentGoal) }
                ?? MorningColumn(day: day, goal: currentGoal)
        }

        // A day with nothing logged has no goal of its own, and showing the
        // current one would spike the goal line in the middle of a week that
        // had a different standard — a missed Tuesday would jut out of an
        // otherwise clean step. Carry the goal across the gap instead:
        // forwards from the last morning that had one, and backwards for any
        // gap before the first.
        var carried: Int?
        for index in columns.indices {
            if byDay[columns[index].day] != nil {
                carried = columns[index].goal
            } else if let carried {
                columns[index].goal = carried
            }
        }
        if let first = columns.firstIndex(where: { byDay[$0.day] != nil }) {
            let goal = columns[first].goal
            for index in columns.indices where index < first {
                columns[index].goal = goal
            }
        }
        return columns
    }
}

/// The plain averages of a set of columns, for the readout when no day is
/// selected. Each figure is over the columns that have it.
nonisolated struct MorningColumnAverages: Equatable {
    var wake: Int?
    var lag: Int?
    var routine: Int?
    /// Days with anything logged at all.
    var count: Int

    init(_ columns: [MorningColumn]) {
        func mean(_ values: [Int]) -> Int? {
            values.isEmpty ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        }
        wake = mean(columns.compactMap(\.wake))
        lag = mean(columns.compactMap(\.lag))
        routine = mean(columns.compactMap(\.routineMinutes))
        count = columns.filter(\.hasAnything).count
    }
}

/// The vertical clock a set of columns shares: whole hours, wide enough for
/// the goal and everything that happened, and never so tight that a quiet
/// week turns ten minutes into half the chart.
nonisolated struct ClockScale: Equatable {
    /// Minutes since the start of the day.
    let lower: Int
    let upper: Int

    static let minimumSpan = 180
    /// Further than this from the middle of the rest, a moment is a stray.
    static let strayDistance = 300

    /// One stray — a test run at two in the afternoon, a routine done in the
    /// evening — used to stretch the clock to fit it, and eleven hours of
    /// clock turned two weeks of mornings into a row of slivers. So the
    /// clock is drawn round the *bulk* of what happened: anything more than
    /// five hours from the median moment is left off it and clamps to the
    /// edge. The goal is always on the clock, and so is everything in
    /// `keeping` — on Today that is today's own column, which is the point of
    /// the chart however unusual the morning.
    ///
    /// - Parameter now: the live edge of a morning still happening, so a
    ///   growing column never runs off the bottom.
    init(columns: [MorningColumn], goal: Int, now: Int? = nil, keeping kept: MorningColumn? = nil) {
        func moments(_ column: MorningColumn) -> [Int] {
            [column.wake, column.start, column.end, column.pausedUntil].compactMap { $0 }
        }
        // Every goal the window covers stays on the clock, so a line that
        // steps is never drawn off the edge.
        let goals = columns.map(\.goal)
        var events = columns.flatMap(moments)
        if events.count >= 3 {
            let sorted = events.sorted()
            let median = sorted[sorted.count / 2]
            events = events.filter { abs($0 - median) <= Self.strayDistance }
        }

        var points = [goal] + goals + events + (kept.map(moments) ?? [])
        if let now { points.append(now) }

        var lo = Int((Double(points.min() ?? goal) / 60).rounded(.down)) * 60
        var hi = Int((Double(points.max() ?? goal) / 60).rounded(.up)) * 60
        // Grow downwards first (later in the day), then upwards, a whole
        // hour at a time.
        var growDown = true
        while hi - lo < Self.minimumSpan {
            if growDown { hi += 60 } else { lo -= 60 }
            growDown.toggle()
        }
        lower = lo
        upper = hi
    }

    /// 0 at the top of the chart, 1 at the bottom; clamped, so a mark that
    /// falls outside the clock stops at the edge rather than escaping it.
    func fraction(_ minutes: Int) -> Double {
        guard upper > lower else { return 0 }
        return min(1, max(0, Double(minutes - lower) / Double(upper - lower)))
    }

    /// The hours to rule and label — every hour, or every other one once
    /// the clock is tall enough for the labels to crowd.
    var hours: [Int] {
        let step = upper - lower > 6 * 60 ? 120 : 60
        return Array(stride(from: lower, through: upper, by: step))
    }
}
