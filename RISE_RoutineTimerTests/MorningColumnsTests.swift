//
//  MorningColumnsTests.swift
//  RISE_RoutineTimerTests
//
//  The upright morning mark and its clock.
//

import XCTest
@testable import RISE_RoutineTimer

final class MorningColumnsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 11:00, the goal these mornings were held to.
    private let goal = 11 * 60

    private func day(_ offset: Int) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func at(_ offset: Int, _ hour: Int, _ minute: Int) -> Date {
        day(offset).addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    /// The owner's Sep 9: woke 12:48, started 2:13, 40:49 of routine, and a
    /// 28-minute pause that pushed the real end to 3:22.
    private var pausedMorning: MorningRecord {
        MorningRecord(
            day: day(0), wakeAt: at(0, 12, 48), routineStartAt: at(0, 14, 13), routineEndAt: at(0, 15, 22),
            completedRoutine: true, routineActiveSeconds: 2449
        )
    }

    func testAColumnIsTheMorningInMinutesIntoItsDay() {
        let column = MorningColumn(record: pausedMorning, currentGoal: goal)

        XCTAssertEqual(column.wake, 12 * 60 + 48)
        XCTAssertEqual(column.start, 14 * 60 + 13)
        XCTAssertEqual(column.lag, 85)
        XCTAssertEqual(column.sessionStart, at(0, 14, 13), "how History finds the run to open")
    }

    /// The box is the routine; the pause is a tail. Drawn to the real end,
    /// the box said 69 minutes beside a readout saying 41.
    func testTheBoxIsTimeSpentAndAPauseIsATail() {
        let column = MorningColumn(record: pausedMorning, currentGoal: goal)

        XCTAssertEqual(column.routineMinutes, 41)
        XCTAssertEqual(column.end, 14 * 60 + 13 + 41)
        XCTAssertEqual(column.pausedUntil, 15 * 60 + 22)
    }

    func testNoPauseMeansNoTail() {
        var record = pausedMorning
        record.routineEndAt = at(0, 14, 54)
        record.routineActiveSeconds = 41 * 60 - 20   // seconds of rounding, not a pause
        XCTAssertNil(MorningColumn(record: record, currentGoal: goal).pausedUntil)

        // Clock times alone: the box runs to the end, and there is no tail.
        record.routineActiveSeconds = nil
        let byTheClock = MorningColumn(record: record, currentGoal: goal)
        XCTAssertEqual(byTheClock.end, 14 * 60 + 54)
        XCTAssertNil(byTheClock.pausedUntil)
    }

    func testAMorningStillHappeningHasOpenEnds() {
        let justAwake = MorningColumn(record: MorningRecord(day: day(0), wakeAt: at(0, 7, 5)), currentGoal: goal)
        XCTAssertEqual(justAwake.wake, 425)
        XCTAssertNil(justAwake.start)
        XCTAssertNil(justAwake.lag)
        XCTAssertTrue(justAwake.hasAnything)

        let running = MorningColumn(record: MorningRecord(day: day(0), wakeAt: at(0, 7, 5), routineStartAt: at(0, 7, 20)), currentGoal: goal)
        XCTAssertEqual(running.lag, 15)
        XCTAssertNil(running.end)
        XCTAssertNil(running.routineMinutes)
    }

    /// A wake time logged after the routine began is a bad entry, not a
    /// negative lag — the same rule the metrics apply.
    func testAWakeAfterTheStartHasNoLag() {
        let column = MorningColumn(record: MorningRecord(day: day(0), wakeAt: at(0, 8, 0), routineStartAt: at(0, 7, 30), routineEndAt: at(0, 8, 0)), currentGoal: goal)
        XCTAssertNil(column.lag)
    }

    func testARunPastMidnightKeepsGoingDownItsColumn() {
        let column = MorningColumn(record: MorningRecord(day: day(0), wakeAt: at(0, 23, 30), routineStartAt: at(0, 23, 50), routineEndAt: at(1, 0, 20)), currentGoal: goal)
        XCTAssertEqual(column.end, 24 * 60 + 20, "not twenty minutes past the top")
    }

    // MARK: - Windows

    func testAWindowHasAColumnForEveryDayAndGapsForTheMissedOnes() {
        let records = [
            MorningRecord(day: day(0), wakeAt: at(0, 7, 0)),
            MorningRecord(day: day(-2), wakeAt: at(-2, 7, 30)),
            MorningRecord(day: day(-9), wakeAt: at(-9, 6, 0)),   // before the window
        ]
        let window = MorningColumn.window(records: records, endingOn: at(0, 15, 0), days: 4, currentGoal: goal, calendar: calendar)

        XCTAssertEqual(window.map(\.day), [day(-3), day(-2), day(-1), day(0)], "oldest first")
        XCTAssertEqual(window.map(\.hasAnything), [false, true, false, true])
        XCTAssertEqual(window[1].wake, 450)
    }

    func testAveragesAreOverTheColumnsThatHaveEachFigure() {
        let averages = MorningColumnAverages([
            MorningColumn(day: day(0), goal: goal, wake: 420, start: 440, end: 470),
            MorningColumn(day: day(-1), goal: goal, wake: 440, start: 480),          // still running: no routine
            MorningColumn(day: day(-2), goal: goal),                                  // a missed day
        ])
        XCTAssertEqual(averages.wake, 430)
        XCTAssertEqual(averages.lag, 30)
        XCTAssertEqual(averages.routine, 30)
        XCTAssertEqual(averages.count, 2)

        let nothing = MorningColumnAverages([MorningColumn(day: day(0), goal: goal)])
        XCTAssertNil(nothing.wake)
        XCTAssertEqual(nothing.count, 0)
    }

    // MARK: - The clock

    func testTheClockIsWholeHoursAroundEverythingThatHappened() {
        let scale = ClockScale(columns: [MorningColumn(record: pausedMorning, currentGoal: goal)], goal: 11 * 60)

        XCTAssertEqual(scale.lower, 11 * 60, "the goal is on the hour")
        XCTAssertEqual(scale.upper, 16 * 60, "3:22 rounds out to four")
        XCTAssertEqual(scale.fraction(11 * 60), 0)
        XCTAssertEqual(scale.fraction(16 * 60), 1)
        XCTAssertEqual(scale.fraction(13 * 60 + 30), 0.5)
        XCTAssertEqual(scale.hours, [660, 720, 780, 840, 900, 960])
    }

    /// A week of mornings within twenty minutes of each other would otherwise
    /// be stretched to fill the chart and look wildly erratic.
    ///
    /// Two hours, not three. At three a real week — seventy minutes from the
    /// earliest cap to the latest end — drew inside the top third of the plot
    /// with the whole bottom half blank, because whole-hour rounding had
    /// already given it two hours before the floor added a third.
    func testAQuietWeekStillGetsTwoHours() {
        let scale = ClockScale(columns: [MorningColumn(day: day(0), goal: 390, wake: 395, start: 405, end: 430)], goal: 390)
        XCTAssertEqual(scale.upper - scale.lower, 120)
        XCTAssertLessThanOrEqual(scale.lower, 360)
        XCTAssertGreaterThanOrEqual(scale.upper, 480)
    }

    /// The floor still bites when a week really is tight: forty minutes
    /// inside a single hour rounds to one hour, and one hour of clock makes
    /// twenty minutes of variation look like chaos.
    func testAWeekInsideOneHourIsStillGivenTwo() {
        let scale = ClockScale(columns: [MorningColumn(day: day(0), goal: 370, wake: 372, start: 380, end: 405)], goal: 370)
        XCTAssertEqual(scale.upper - scale.lower, 120)
    }

    func testAGrowingColumnStaysOnTheClockAndStraysAreClamped() {
        let columns = [MorningColumn(day: day(0), goal: 390, wake: 400)]
        let live = ClockScale(columns: columns, goal: 390, now: 655)
        XCTAssertGreaterThanOrEqual(live.upper, 655)

        let still = ClockScale(columns: columns, goal: 390)
        XCTAssertEqual(still.fraction(2000), 1, "off the bottom stops at the edge")
        XCTAssertEqual(still.fraction(-50), 0)
    }

    /// Found on the first real look: one test run at 1:45 in the afternoon
    /// stretched a fortnight's clock from 3 AM to 2 PM.
    func testOneStrayRunDoesNotStretchTheClock() {
        let columns = [
            MorningColumn(day: day(-3), goal: 390, wake: 395, start: 407, end: 428),
            MorningColumn(day: day(-2), goal: 390, wake: 410, start: 420, end: 445),
            MorningColumn(day: day(-1), goal: 390, wake: 400, start: 415, end: 440),
            MorningColumn(day: day(0), goal: 390, start: 824, end: 832),            // the stray
        ]
        let scale = ClockScale(columns: columns, goal: 390)

        XCTAssertLessThanOrEqual(scale.upper, 9 * 60, "the clock stays round the mornings")
        XCTAssertEqual(scale.fraction(824), 1, "and the stray clamps to the edge")
    }

    /// Today's own column is the point of Today's chart, however odd the day.
    func testTheKeptColumnIsAlwaysOnTheClock() {
        let week = [
            MorningColumn(day: day(-3), goal: 390, wake: 395, start: 407, end: 428),
            MorningColumn(day: day(-2), goal: 390, wake: 410, start: 420, end: 445),
            MorningColumn(day: day(-1), goal: 390, wake: 400, start: 415, end: 440),
        ]
        let today = MorningColumn(day: day(0), goal: 390, wake: 780, start: 800)
        let scale = ClockScale(columns: week + [today], goal: 390, now: 815, keeping: today)

        XCTAssertGreaterThanOrEqual(scale.upper, 815)
        XCTAssertLessThan(scale.fraction(780), 1)
    }

    func testTheGoalIsOnTheClockEvenWhenNobodyGoesNearIt() {
        let columns = (0..<4).map { MorningColumn(day: day(-$0), goal: 390, wake: 700 + $0 * 5, start: 730, end: 760) }
        let scale = ClockScale(columns: columns, goal: 390)
        XCTAssertLessThanOrEqual(scale.lower, 390)
    }

    func testALongClockLabelsEveryOtherHour() {
        let scale = ClockScale(columns: [MorningColumn(day: day(0), goal: 390, wake: 300, start: 800, end: 830)], goal: 390)
        XCTAssertEqual(scale.hours.count, (scale.upper - scale.lower) / 120 + 1)
    }

    /// A window spans a goal change, so the chart can draw the step.
    func testColumnsCarryTheGoalEachMorningWasHeldTo() {
        let records = [
            MorningRecord(day: day(-2), wakeAt: at(-2, 7, 30), goalMinutes: 7 * 60),
            MorningRecord(day: day(-1), wakeAt: at(-1, 7, 0), goalMinutes: 7 * 60),
            MorningRecord(day: day(0), wakeAt: at(0, 6, 40), goalMinutes: 6 * 60 + 30),
        ]
        let window = MorningColumn.window(
            records: records, endingOn: at(0, 12, 0), days: 3,
            currentGoal: 6 * 60 + 30, calendar: calendar
        )

        XCTAssertEqual(window.map(\.goal), [7 * 60, 7 * 60, 6 * 60 + 30], "the bar was raised on the last day")

        // With nothing logged at all, every column shows the goal in force now.
        let empty = MorningColumn.window(
            records: [], endingOn: at(0, 12, 0), days: 2,
            currentGoal: 6 * 60 + 30, calendar: calendar
        )
        XCTAssertEqual(empty.map(\.goal), [6 * 60 + 30, 6 * 60 + 30])
    }

    /// A missed day used to show *today's* goal, which spiked the goal line
    /// in the middle of a week that had been held to a different standard.
    func testAMissedDayCarriesTheGoalAcrossTheGap() {
        let records = [
            MorningRecord(day: day(-4), wakeAt: at(-4, 7, 30), goalMinutes: 7 * 60),
            // day(-3) and day(-2) missed
            MorningRecord(day: day(-1), wakeAt: at(-1, 6, 40), goalMinutes: 6 * 60),
        ]
        let window = MorningColumn.window(
            records: records, endingOn: at(-1, 12, 0), days: 4,
            currentGoal: 5 * 60, calendar: calendar
        )

        XCTAssertEqual(window.map(\.goal), [7 * 60, 7 * 60, 7 * 60, 6 * 60],
                       "the gap keeps the standard it was under, and steps once")
    }

    /// A gap *before* the first logged morning takes that morning's goal
    /// rather than today's.
    func testAGapBeforeTheFirstMorningLooksForward() {
        let records = [MorningRecord(day: day(0), wakeAt: at(0, 7, 30), goalMinutes: 7 * 60)]
        let window = MorningColumn.window(
            records: records, endingOn: at(0, 12, 0), days: 3,
            currentGoal: 5 * 60, calendar: calendar
        )
        XCTAssertEqual(window.map(\.goal), [7 * 60, 7 * 60, 7 * 60])
    }

    /// Every goal in the window has to stay on the clock, or a stepped line
    /// gets drawn off the edge of the chart.
    func testTheClockCoversEveryGoalInTheWindow() {
        let columns = [
            MorningColumn(day: day(-1), goal: 9 * 60, wake: 9 * 60 + 5, start: 9 * 60 + 15, end: 9 * 60 + 40),
            MorningColumn(day: day(0), goal: 6 * 60, wake: 6 * 60 + 10, start: 6 * 60 + 20, end: 6 * 60 + 45),
        ]
        let scale = ClockScale(columns: columns, goal: 6 * 60)

        XCTAssertLessThanOrEqual(scale.lower, 6 * 60)
        XCTAssertGreaterThanOrEqual(scale.upper, 9 * 60)
        XCTAssertGreaterThan(scale.fraction(9 * 60), 0)
        XCTAssertLessThan(scale.fraction(9 * 60), 1)
    }
}
