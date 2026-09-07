//
//  TargetScheduleTests.swift
//  RISE_RoutineTimerTests
//

import XCTest
@testable import RISE_RoutineTimer

final class TargetScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: hour, minute: minute))!
    }

    func testUnsetTargetYieldsNothing() {
        let schedule = TargetSchedule(targetMinutesAfterMidnight: TargetSchedule.none, calendar: calendar)
        XCTAssertFalse(schedule.isSet)
        XCTAssertNil(schedule.targetDate(on: date(hour: 6, minute: 0)))
        XCTAssertNil(schedule.startByDate(on: date(hour: 6, minute: 0), plannedSeconds: 600))
        XCTAssertNil(schedule.spareSeconds(projectedEnd: date(hour: 7, minute: 0)))
        XCTAssertNil(schedule.startByComponents(plannedSeconds: 600))
    }

    func testStartByAndSpare() {
        let schedule = TargetSchedule(targetMinutesAfterMidnight: 7 * 60 + 30, calendar: calendar)
        XCTAssertEqual(schedule.targetDate(on: date(hour: 5, minute: 12)), date(hour: 7, minute: 30))
        XCTAssertEqual(schedule.startByDate(on: date(hour: 5, minute: 12), plannedSeconds: 22 * 60), date(hour: 7, minute: 8))
        XCTAssertEqual(schedule.spareSeconds(projectedEnd: date(hour: 7, minute: 26)), 240)
        XCTAssertEqual(schedule.spareSeconds(projectedEnd: date(hour: 7, minute: 33)), -180)
        XCTAssertNil(schedule.spareSeconds(projectedEnd: date(hour: 20, minute: 0)), "far-off runs get no label")
    }

    func testReminderComponentsWrapAroundMidnight() {
        let schedule = TargetSchedule(targetMinutesAfterMidnight: 7 * 60 + 30, calendar: calendar)
        XCTAssertEqual(schedule.startByComponents(plannedSeconds: 22 * 60), DateComponents(hour: 7, minute: 8))
        let earlyBird = TargetSchedule(targetMinutesAfterMidnight: 10, calendar: calendar)
        XCTAssertEqual(earlyBird.startByComponents(plannedSeconds: 30 * 60), DateComponents(hour: 23, minute: 40))
    }

    func testSpareText() {
        XCTAssertEqual(TargetSchedule.spareText(10), "ON TARGET")
        XCTAssertEqual(TargetSchedule.spareText(240), "4:00 TO SPARE")
        XCTAssertEqual(TargetSchedule.spareText(-180), "3:00 PAST TARGET")
    }

    func testIconNormalization() {
        XCTAssertEqual(RoutineStep.normalizedIcon(" 🧘‍♂️abc"), "🧘‍♂️")
        XCTAssertEqual(RoutineStep.normalizedIcon("   "), "")
    }
}
