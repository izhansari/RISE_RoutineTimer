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
        store.recordWake(at: at(6, 35), existing: [], goalMinutes: settings.targetWakeMinutes)

        XCTAssertFalse(store.recordWakeImplied(byRoutineStartingAt: at(6, 50), settings: settings))
        XCTAssertEqual(try logs().map(\.wakeAt), [at(6, 35)])
    }

    /// Undoing "I'm awake" leaves a row with no wake time; a run started
    /// after that fills the same row rather than adding a second one.
    func testRunStartFillsAnUndoneWakeTime() throws {
        let store = MorningLogStore(context: container.mainContext, calendar: calendar)
        store.recordWake(at: at(6, 35), existing: [], goalMinutes: settings.targetWakeMinutes)
        store.setWake(nil, on: at(6, 40), existing: try logs(), goalMinutes: settings.targetWakeMinutes)

        XCTAssertTrue(store.recordWakeImplied(byRoutineStartingAt: at(6, 50), settings: settings))
        XCTAssertEqual(try logs().map(\.wakeAt), [at(6, 50)])
    }

    func testAnEveningRunLogsNothing() throws {
        let store = MorningLogStore(context: container.mainContext, calendar: calendar)
        XCTAssertFalse(store.recordWakeImplied(byRoutineStartingAt: at(19, 0), settings: settings))
        XCTAssertTrue(try logs().isEmpty)
    }

    /// The join is where a session's measured time reaches the morning's
    /// record — the chart, the Today tile and the baselines all read it there.
    func testJoiningCarriesTheSessionsActiveTimeNotJustItsClockTimes() {
        let start = at(14, 13)
        let session = RoutineSession(result: SessionResult(
            startedAt: start, endedAt: start.addingTimeInterval(4147),
            plannedSeconds: 2645, activeSeconds: 2449, pausedSeconds: 1698,
            completed: true, steps: []
        ))

        let records = MorningRecord.join(logs: [], sessions: [session], calendar: calendar)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].routineActiveSeconds, 2449)
        XCTAssertEqual(records[0].durationMinutes, 41)
    }

    // MARK: - The goal is recorded with the morning

    /// The whole point: moving the goal must not rewrite what came before.
    /// Without this, walking the wake time earlier erased the evidence of
    /// every step you had already taken.
    func testMovingTheGoalLeavesRecordedMorningsAlone() throws {
        let store = MorningLogStore(context: container.mainContext, calendar: calendar)
        store.recordWake(at: at(7, 0), existing: [], goalMinutes: 6 * 60 + 30)

        let logged = try logs()
        XCTAssertEqual(logged.map(\.goalMinutes), [6 * 60 + 30])

        // Scored against the goal it was held to: 30 minutes late.
        let strict = MorningSettings(targetWakeMinutes: 6 * 60 + 30)
        var record = MorningRecord.join(logs: logged, sessions: [], calendar: calendar)[0]
        XCTAssertEqual(record.snoozeMinutes(settings: strict, calendar: calendar), 30)

        // The goal moves an hour later; that morning is still 30 late.
        let relaxed = MorningSettings(targetWakeMinutes: 7 * 60 + 30)
        XCTAssertEqual(record.snoozeMinutes(settings: relaxed, calendar: calendar), 30,
                       "history is not rewritten by today's standard")

        // Only a morning with no goal of its own follows the current one.
        record.goalMinutes = nil
        XCTAssertEqual(record.snoozeMinutes(settings: relaxed, calendar: calendar), -30)
    }

    func testARunStartLogsTheGoalTooAndUndoKeepsIt() throws {
        let store = MorningLogStore(context: container.mainContext, calendar: calendar)
        XCTAssertTrue(store.recordWakeImplied(byRoutineStartingAt: at(6, 50), settings: settings))
        XCTAssertEqual(try logs().map(\.goalMinutes), [settings.targetWakeMinutes])

        // Undoing the wake leaves the goal on the row: the morning still
        // happened under it.
        store.setWake(nil, on: at(6, 55), existing: try logs(), goalMinutes: settings.targetWakeMinutes)
        XCTAssertEqual(try logs().map(\.wakeAt), [nil])
        XCTAssertEqual(try logs().map(\.goalMinutes), [settings.targetWakeMinutes])
    }
}
