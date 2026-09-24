//
//  EveningTests.swift
//  RISE_RoutineTimerTests
//
//  When the Today tab turns to the night, and what it says then.
//

import XCTest
@testable import RISE_RoutineTimer

final class EveningTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testTheEveningRunsFromItsStartThroughMidnightToFour() {
        let seven = 19 * 60
        XCTAssertFalse(NightSettings.isEvening(at(23, 18, 59), eveningStartMinutes: seven, calendar: calendar))
        XCTAssertTrue(NightSettings.isEvening(at(23, 19, 0), eveningStartMinutes: seven, calendar: calendar))
        XCTAssertTrue(NightSettings.isEvening(at(23, 23, 59), eveningStartMinutes: seven, calendar: calendar))
        XCTAssertTrue(NightSettings.isEvening(at(24, 0, 30), eveningStartMinutes: seven, calendar: calendar), "half past midnight is still tonight")
        XCTAssertTrue(NightSettings.isEvening(at(24, 3, 59), eveningStartMinutes: seven, calendar: calendar))
        XCTAssertFalse(NightSettings.isEvening(at(24, 4, 0), eveningStartMinutes: seven, calendar: calendar), "the morning takes over at four")
        XCTAssertFalse(NightSettings.isEvening(at(24, 12, 0), eveningStartMinutes: seven, calendar: calendar))
    }

    /// An evening start at or before 4am would swallow the whole day; it is
    /// read as "never" instead.
    func testAnEveningStartBeforeFourIsNever() {
        XCTAssertFalse(NightSettings.isEvening(at(23, 2, 0), eveningStartMinutes: 3 * 60, calendar: calendar))
        XCTAssertFalse(NightSettings.isEvening(at(23, 12, 0), eveningStartMinutes: 0, calendar: calendar))
    }

    func testStartingNowFinishesByThePlanAndTheUsual() {
        let now = at(23, 21, 15)
        let outlook = NightOutlook(now: now, plannedSeconds: 42 * 60, usualSeconds: 38 * 60, goalMinutes: 22 * 60, calendar: calendar)
        XCTAssertEqual(outlook.finishOnPlan, at(23, 21, 57))
        XCTAssertEqual(outlook.finishAsUsual, at(23, 21, 53))
        XCTAssertEqual(outlook.goal, at(23, 22, 0))
        XCTAssertEqual(outlook.minutesToGoal, 45)

        let noUsual = NightOutlook(now: now, plannedSeconds: 60, usualSeconds: nil, goalMinutes: 22 * 60, calendar: calendar)
        XCTAssertNil(noUsual.finishAsUsual)
    }

    /// After midnight the goal that counts is the one just past — tonight's
    /// 10pm — not tomorrow's, which would read as 21 hours to go.
    func testPastMidnightTheGoalIsTheOneJustPassed() {
        let outlook = NightOutlook(now: at(24, 0, 30), plannedSeconds: 1800, usualSeconds: nil, goalMinutes: 22 * 60, calendar: calendar)
        XCTAssertEqual(outlook.goal, at(23, 22, 0))
        XCTAssertEqual(outlook.minutesToGoal, -150)
    }
}
