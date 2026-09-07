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
}
