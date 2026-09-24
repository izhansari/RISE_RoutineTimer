//
//  MorningMetricsTests.swift
//  RISE_RoutineTimerTests
//
//  Checks the ported MorningCheckin math against hand-computed numbers.
//

import XCTest
@testable import RISE_RoutineTimer

final class MorningMetricsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1 // Sunday, matching the web app's week start.
        return c
    }

    /// Target wake is 6:30am throughout.
    private var settings: MorningSettings {
        MorningSettings(targetWakeMinutes: 6 * 60 + 30, snoozeBudgetMinutes: 60, activationBudgetMinutes: 60)
    }

    /// 2026-09-06 is a Sunday, so `now` sits on the first day of its week.
    private func now() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: now())!)
    }

    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day(dayOffset))!
    }

    /// Wakes at 6:45 (+15 snooze), starts 6:55 (10 min activation), ends 7:20 (25 min).
    private func record(
        _ offset: Int,
        wake: (Int, Int)? = (6, 45),
        start: (Int, Int)? = (6, 55),
        end: (Int, Int)? = (7, 20),
        completed: Bool = true
    ) -> MorningRecord {
        MorningRecord(
            day: day(offset),
            wakeAt: wake.map { at(offset, $0.0, $0.1) },
            routineStartAt: start.map { at(offset, $0.0, $0.1) },
            routineEndAt: end.map { at(offset, $0.0, $0.1) },
            completedRoutine: completed
        )
    }

    private func metrics(_ records: [MorningRecord]) -> MorningMetrics {
        MorningMetrics(records: records, settings: settings, calendar: calendar)
    }

    // MARK: - Per-day metrics

    func testSnoozeIsMinutesPastTarget() {
        XCTAssertEqual(record(0).snoozeMinutes(settings: settings, calendar: calendar), 15)
    }

    func testWakingEarlyGivesNegativeSnooze() {
        let early = record(0, wake: (6, 10))
        XCTAssertEqual(early.snoozeMinutes(settings: settings, calendar: calendar), -20)
    }

    func testActivationAndDuration() {
        XCTAssertEqual(record(0).activationMinutes, 10)
        XCTAssertEqual(record(0).durationMinutes, 25)
    }

    func testRoutineStartingBeforeWakeHasNoActivation() {
        // A wake time logged late can land after the routine already started.
        // That is a bad entry to fix, not a negative activation.
        let inconsistent = record(0, wake: (7, 30), start: (6, 55))
        XCTAssertNil(inconsistent.activationMinutes)
        XCTAssertFalse(inconsistent.isComplete == false && inconsistent.wakeAt == nil)
    }

    func testMissingTimestampsYieldNil() {
        let partial = record(0, start: nil, end: nil)
        XCTAssertEqual(partial.snoozeMinutes(settings: settings, calendar: calendar), 15)
        XCTAssertNil(partial.activationMinutes)
        XCTAssertNil(partial.durationMinutes)
        XCTAssertFalse(partial.isComplete)
        XCTAssertTrue(partial.hasAnything)
    }

    // MARK: - Baselines

    func testRollingAverageOverWindow() {
        // Snooze of +15, +45, and +0 over three consecutive days → mean +20.
        let m = metrics([
            record(0, wake: (6, 45)),
            record(-1, wake: (7, 15)),
            record(-2, wake: (6, 30))
        ])
        XCTAssertEqual(m.rollingAverage(.snooze, days: 7, now: now()), 20)
    }

    func testRollingAverageIgnoresDaysOutsideWindow() {
        let m = metrics([
            record(0, wake: (6, 45)),      // +15, inside
            record(-30, wake: (8, 30))     // +120, outside a 7-day window
        ])
        XCTAssertEqual(m.rollingAverage(.snooze, days: 7, now: now()), 15)
    }

    func testRollingAverageIgnoresIncompleteDays() {
        let m = metrics([
            record(0, wake: (6, 45)),
            record(-1, wake: (8, 30), start: nil, end: nil)
        ])
        XCTAssertEqual(m.rollingAverage(.snooze, days: 7, now: now()), 15)
    }

    func testRollingAverageCanExcludeToday() {
        let m = metrics([
            record(0, wake: (7, 30)),   // +60 today
            record(-1, wake: (6, 40))   // +10 yesterday
        ])
        XCTAssertEqual(m.rollingAverage(.snooze, days: 7, now: now(), excluding: now()), 10)
    }

    func testRollingAverageIsNilWithNoData() {
        XCTAssertNil(metrics([]).rollingAverage(.snooze, days: 7, now: now()))
    }

    func testPreviousValueSkipsToday() {
        let m = metrics([record(0, wake: (7, 30)), record(-1, wake: (6, 40))])
        XCTAssertEqual(m.previousValue(.snooze, now: now()), 10)
    }

    // MARK: - Consistency

    func testWakeConsistencyIsPopulationStandardDeviation() {
        // Wake at 6:00 and 7:00 → minutes 360 and 420, mean 390, sd 30.
        let m = metrics([
            record(0, wake: (6, 0)),
            record(-1, wake: (7, 0))
        ])
        XCTAssertEqual(m.wakeConsistencyMinutes(days: 7, now: now()), 30)
    }

    func testWakeConsistencyNeedsTwoDays() {
        XCTAssertNil(metrics([record(0)]).wakeConsistencyMinutes(days: 7, now: now()))
    }

    func testAverageWakeMinutes() {
        let m = metrics([record(0, wake: (6, 0)), record(-1, wake: (7, 0))])
        XCTAssertEqual(m.averageWakeMinutes(days: 7, now: now()), 390)
    }

    // MARK: - Budgets

    func testWeeklyBudgetCountsOnlyOverruns() {
        // now() is a Sunday, so day(0) is the only day in this week.
        let m = metrics([
            record(0, wake: (6, 50)),   // +20, counts
            record(-1, wake: (8, 0))    // previous week, ignored
        ])
        XCTAssertEqual(m.weeklyBudgetUsed(.snooze, now: now()), 20)
    }

    func testEarlyMorningsDoNotEarnBudgetCredit() {
        let m = metrics([record(0, wake: (5, 30))])   // −60
        XCTAssertEqual(m.weeklyBudgetUsed(.snooze, now: now()), 0)
    }

    // MARK: - Missed days

    func testMissedDaysCountsGapsButNotToday() {
        // Logged 4 and 2 days ago; days −3 and −1 are gaps. Today is excluded.
        let m = metrics([record(-4), record(-2)])
        let missed = m.missedDays(now: now())
        XCTAssertEqual(missed.allTime, 2)
    }

    func testNoMissedDaysWithNothingLogged() {
        XCTAssertEqual(metrics([]).missedDays(now: now()), MorningMetrics.MissedDays())
    }

    // MARK: - Streak

    func testStreakCountsConsecutiveCompletedDays() {
        let m = metrics([record(0), record(-1), record(-2), record(-4)])
        XCTAssertEqual(m.currentStreak(now: now()), 3)
    }

    func testStreakSurvivesARoutineNotYetRunToday() {
        let m = metrics([record(-1), record(-2)])
        XCTAssertEqual(m.currentStreak(now: now()), 2)
    }

    func testStreakIgnoresAbandonedRuns() {
        let m = metrics([record(0, completed: false), record(-1), record(-2)])
        XCTAssertEqual(m.currentStreak(now: now()), 2)
    }

    // MARK: - Insights

    func testInsightsMentionTotalAndLatencyStreak() {
        // The streak rule is activation *under* 10 min, so 7-minute mornings.
        let m = metrics([
            record(0, start: (6, 52)),
            record(-1, start: (6, 52)),
            record(-2, start: (6, 52))
        ])
        let lines = m.insights(now: now())
        XCTAssertTrue(lines.contains { $0.contains("3 mornings") })
        XCTAssertTrue(lines.contains { $0.contains("3 days in a row") })
    }

    func testInsightsFallBackWithNoData() {
        XCTAssertEqual(metrics([]).insights(now: now()).count, 1)
    }

    // MARK: - Routine length is time spent doing it

    /// The morning this was found on: started 2:13, ended 3:22, with a
    /// 28-minute pause in the middle. 69 minutes on the clock, 41 of routine.
    func testAPauseIsNotRoutineTime() {
        var morning = record(0, start: (14, 13), end: (15, 22))
        XCTAssertEqual(morning.durationMinutes, 69, "clock times alone: all there is to go on")

        morning.routineActiveSeconds = 2449
        XCTAssertEqual(morning.durationMinutes, 41, "the timer measured 40:49 of routine")
        XCTAssertEqual(metrics([morning]).value(.duration, for: morning), 41)
    }

    /// With no pause, active time and the clock agree — which is every
    /// morning the web app can describe, so the two apps still match.
    func testWithoutAPauseActiveTimeAndTheClockAgree() {
        var morning = record(0)
        let byTheClock = morning.durationMinutes
        morning.routineActiveSeconds = 25 * 60
        XCTAssertEqual(morning.durationMinutes, byTheClock)
    }

    func testRoutineLengthStillNeedsBothEnds() {
        var running = record(0, end: nil)
        running.routineActiveSeconds = 600
        XCTAssertNil(running.durationMinutes, "not a finished morning yet")
    }

    // MARK: - A routine start implies a wake time

    func testStartingTheRoutineImpliesAWakeTimeWhenNoneIsLogged() {
        let start = at(0, 6, 50)
        XCTAssertEqual(settings.impliedWake(routineStart: start, existingWake: nil, calendar: calendar), start)

        // Up before the target still counts: that is a negative snooze.
        let early = at(0, 5, 40)
        XCTAssertEqual(settings.impliedWake(routineStart: early, existingWake: nil, calendar: calendar), early)
    }

    func testALoggedWakeTimeIsNeverReplaced() {
        XCTAssertNil(settings.impliedWake(routineStart: at(0, 6, 50), existingWake: at(0, 6, 35), calendar: calendar))
    }

    /// An evening run against a 6:30 target would otherwise put a twelve-hour
    /// snooze into the week's budget.
    func testARunOutsideTheMorningImpliesNothing() {
        XCTAssertNil(settings.impliedWake(routineStart: at(0, 19, 0), existingWake: nil, calendar: calendar))
        XCTAssertNil(settings.impliedWake(routineStart: at(0, 0, 20), existingWake: nil, calendar: calendar))
        // The window's edges are inside it: 12:30am and 12:30pm for a 6:30 target.
        XCTAssertNotNil(settings.impliedWake(routineStart: at(0, 12, 30), existingWake: nil, calendar: calendar))
        XCTAssertNotNil(settings.impliedWake(routineStart: at(0, 0, 30), existingWake: nil, calendar: calendar))
    }

    // MARK: - The night, in the morning's shape

    /// A night record's "wake" is the moment its routine began, and its
    /// snooze is measured from the record's own day — so a night that
    /// started at half past midnight is 150 minutes late against 10pm, not
    /// 21 hours early against the next day's midnight.
    func testANightPastMidnightIsLateNotEarly() {
        let nightGoal = MorningSettings(targetWakeMinutes: 22 * 60)
        let evening = day(0)
        var night = MorningRecord(day: evening)
        night.wakeAt = evening.addingTimeInterval(24.5 * 3600)      // 12:30am, the next calendar day
        night.routineStartAt = night.wakeAt
        night.routineEndAt = night.wakeAt?.addingTimeInterval(30 * 60)
        night.goalMinutes = 22 * 60

        XCTAssertEqual(night.snoozeMinutes(settings: nightGoal, calendar: calendar), 150)
        XCTAssertEqual(night.activationMinutes, 0)
        XCTAssertEqual(night.durationMinutes, 30)
        XCTAssertEqual(night.wakeMinutesAfterMidnight(calendar: calendar), 1470, "into the night's day, not the clock's")
        XCTAssertTrue(night.isComplete)

        // A morning is unchanged by the day-relative rule.
        let morning = record(0, wake: (6, 50), start: (7, 0), end: (7, 30))
        XCTAssertEqual(morning.snoozeMinutes(settings: settings, calendar: calendar), 20)
        XCTAssertEqual(morning.wakeMinutesAfterMidnight(calendar: calendar), 6 * 60 + 50)
    }

    /// The night has no activation, and says "nights", not "mornings".
    func testNightMetricsSpeakOfNightsAndSkipActivation() {
        var records: [MorningRecord] = []
        for index in 0..<8 {
            var night = MorningRecord(day: day(-index))
            night.wakeAt = day(-index).addingTimeInterval(TimeInterval(22 * 3600 + 5 * 60))
            night.routineStartAt = night.wakeAt
            night.routineEndAt = night.wakeAt?.addingTimeInterval(30 * 60)
            night.completedRoutine = true
            night.goalMinutes = 22 * 60
            records.append(night)
        }
        let metrics = MorningMetrics(records: records, settings: MorningSettings(targetWakeMinutes: 22 * 60), calendar: calendar, kind: .night)

        XCTAssertEqual(metrics.metrics, [.snooze, .duration])
        let lines = metrics.insights(now: day(0).addingTimeInterval(23 * 3600))
        XCTAssertEqual(lines.first, "You've logged 8 nights total.")
        XCTAssertFalse(lines.contains { $0.hasPrefix("Activation") }, "nothing to activate from at night")
        XCTAssertTrue(lines.contains { $0.contains("spread in start time") }, "\(lines)")

        let morning = MorningMetrics(records: records, settings: MorningSettings(targetWakeMinutes: 22 * 60), calendar: calendar)
        XCTAssertEqual(morning.metrics, MorningMetrics.Metric.allCases)
        XCTAssertEqual(morning.insights(now: day(0).addingTimeInterval(23 * 3600)).first, "You've logged 8 mornings total.")
    }

    /// The night routine says nothing about waking, however early it runs —
    /// a night run at 12:30am is inside the morning window and must still
    /// not become the day's wake time.
    func testANightRunNeverImpliesAWake() {
        XCTAssertNil(settings.impliedWake(routineStart: at(0, 6, 50), kind: .night, existingWake: nil, calendar: calendar))
        XCTAssertNil(settings.impliedWake(routineStart: at(0, 0, 30), kind: .night, existingWake: nil, calendar: calendar))
        XCTAssertNotNil(settings.impliedWake(routineStart: at(0, 6, 50), kind: .morning, existingWake: nil, calendar: calendar))
    }

    /// The point of it: a morning started from the Run tab is a complete
    /// record, so it reaches the baselines instead of being dropped.
    func testAnImpliedWakeMakesTheMorningCount() {
        let start = at(0, 6, 50)
        let wake = settings.impliedWake(routineStart: start, existingWake: nil, calendar: calendar)
        let morning = MorningRecord(day: day(0), wakeAt: wake, routineStartAt: start, routineEndAt: at(0, 7, 30), completedRoutine: true)
        XCTAssertTrue(morning.isComplete)
        XCTAssertEqual(morning.snoozeMinutes(settings: settings, calendar: calendar), 20)
        XCTAssertEqual(morning.activationMinutes, 0)
    }

    // MARK: - Today's finished figures

    /// A morning that began five hours before the goal printed a
    /// nine-character `−5:09:57` and ran into the next column.
    func testAFinishedFigureIsMinutesAndStaysShort() {
        XCTAssertEqual(TodayView.minuteText(42), "42 MIN")
        XCTAssertEqual(TodayView.minuteText(0), "0 MIN")
        XCTAssertEqual(TodayView.minuteText(59), "59 MIN")
        XCTAssertEqual(TodayView.minuteText(60), "1:00")
        XCTAssertEqual(TodayView.minuteText(80), "1:20")

        XCTAssertEqual(TodayView.minuteText(52, signed: true), "+52 MIN")
        XCTAssertEqual(TodayView.minuteText(-310, signed: true), "−5:10", "up five hours early")
        XCTAssertEqual(TodayView.minuteText(-20, signed: true), "−20 MIN")
        XCTAssertEqual(TodayView.minuteText(0, signed: true), "0 MIN", "on the goal takes no sign")

        for minutes in [-310, -20, 0, 42, 52, 80, 125] {
            XCTAssertLessThanOrEqual(TodayView.minuteText(minutes, signed: true).count, 7)
        }
    }

    /// Today's own share has to be separable from the rest of the week, so
    /// the Today tab can draw the week already spent and then today growing
    /// on the end of it.
    func testABudgetCanLeaveTodayOut() {
        // Sun 6th is the start of the week here; wakes at 6:45 are +15 each.
        let m = metrics([record(0), record(-1), record(-2)])

        XCTAssertEqual(m.weeklyBudgetUsed(.snooze, now: now()), 15, "only the 6th is in this week")
        XCTAssertEqual(m.weeklyBudgetUsed(.snooze, now: now(), excluding: now()), 0, "…and that is today")

        // A fuller week, today included and then held back.
        let week = metrics([record(0), record(-1), record(-2), record(-3)])
        let all = week.weeklyBudgetUsed(.activation, now: now())
        let before = week.weeklyBudgetUsed(.activation, now: now(), excluding: now())
        XCTAssertEqual(all - before, 10, "today's activation is 10 min")
    }
}
