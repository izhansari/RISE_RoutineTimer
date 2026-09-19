//
//  MorningLogStoreTests.swift
//  RISE_RoutineTimerTests
//
//  The store's side of "starting the routine means you are awake", against an
//  in-memory SwiftData container.
//

import SwiftData
import XCTest
@testable import RISE_RoutineTimer

@MainActor
final class MorningLogStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let settings = MorningSettings(targetWakeMinutes: 6 * 60 + 30)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: MorningLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: hour, minute: minute))!
    }

    private func logs() throws -> [MorningLog] {
        try container.mainContext.fetch(FetchDescriptor<MorningLog>())
    }

    func testRunStartLogsTheWakeTimeOnce() throws {
        let store = MorningLogStore(context: container.mainContext, calendar: calendar)

        XCTAssertTrue(store.recordWakeImplied(byRoutineStartingAt: at(6, 50), settings: settings))
        XCTAssertEqual(try logs().map(\.wakeAt), [at(6, 50)])

        // A second run the same morning leaves the first answer alone.
        XCTAssertFalse(store.recordWakeImplied(byRoutineStartingAt: at(8, 15), settings: settings))
        XCTAssertEqual(try logs().map(\.wakeAt), [at(6, 50)])
    }

    func testRunStartNeverOverwritesATappedWakeTime() throws {
        let store = MorningLogStore(context: container.mainContext, calendar: calendar)
        store.recordWake(at: at(6, 35), existing: [])

        XCTAssertFalse(store.recordWakeImplied(byRoutineStartingAt: at(6, 50), settings: settings))
        XCTAssertEqual(try logs().map(\.wakeAt), [at(6, 35)])
    }

    /// Undoing "I'm awake" leaves a row with no wake time; a run started
    /// after that fills the same row rather than adding a second one.
    func testRunStartFillsAnUndoneWakeTime() throws {
        let store = MorningLogStore(context: container.mainContext, calendar: calendar)
        store.recordWake(at: at(6, 35), existing: [])
        store.setWake(nil, on: at(6, 40), existing: try logs())

        XCTAssertTrue(store.recordWakeImplied(byRoutineStartingAt: at(6, 50), settings: settings))
        XCTAssertEqual(try logs().map(\.wakeAt), [at(6, 50)])
    }

    func testAnEveningRunLogsNothing() throws {
        let store = MorningLogStore(context: container.mainContext, calendar: calendar)
        XCTAssertFalse(store.recordWakeImplied(byRoutineStartingAt: at(19, 0), settings: settings))
        XCTAssertTrue(try logs().isEmpty)
    }
}
