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

    // MARK: - The night routine stays out of the morning

    /// Starting the night routine is not waking up, even when it happens
    /// inside the morning window.
    func testANightRunLogsNoWakeTime() throws {
        let store = MorningLogStore(context: container.mainContext, calendar: calendar)
        XCTAssertFalse(store.recordWakeImplied(byRoutineStartingAt: at(6, 50), kind: .night, settings: settings))
        XCTAssertTrue(try logs().isEmpty)

        // And the morning one still does.
        XCTAssertTrue(store.recordWakeImplied(byRoutineStartingAt: at(6, 55), kind: .morning, settings: settings))
        XCTAssertEqual(try logs().map(\.wakeAt), [at(6, 55)])
    }

    /// A night session on a day with no morning run would otherwise become
    /// that day's routine start, and on a day with one it would be the
    /// earlier-run-wins contest's loser only by luck of the clock.
    func testJoiningLeavesNightSessionsOut() {
        let morning = RoutineSession(result: SessionResult(
            startedAt: at(6, 50), endedAt: at(7, 20),
            plannedSeconds: 1800, activeSeconds: 1800, pausedSeconds: 0,
            completed: true, steps: [], kind: .morning
        ))
        let night = RoutineSession(result: SessionResult(
            startedAt: at(22, 0), endedAt: at(22, 40),
            plannedSeconds: 2400, activeSeconds: 2400, pausedSeconds: 0,
            completed: true, steps: [], kind: .night
        ))

        let both = MorningRecord.join(logs: [], sessions: [night, morning], calendar: calendar)
        XCTAssertEqual(both.count, 1)
        XCTAssertEqual(both[0].routineStartAt, at(6, 50))

        XCTAssertTrue(MorningRecord.join(logs: [], sessions: [night], calendar: calendar).isEmpty)
    }

    /// A night belongs to the evening it began on: the day turns over at
    /// noon, so half past midnight is still the night before.
    func testANightsDayTurnsOverAtNoon() {
        let sixth = calendar.startOfDay(for: at(12, 0))
        let seventh = calendar.date(byAdding: .day, value: 1, to: sixth)!
        XCTAssertEqual(MorningRecord.nightDay(of: at(22, 30), calendar: calendar), sixth)
        XCTAssertEqual(MorningRecord.nightDay(of: at(23, 59), calendar: calendar), sixth)
        XCTAssertEqual(MorningRecord.nightDay(of: seventh.addingTimeInterval(30 * 60), calendar: calendar), sixth, "12:30am is the 6th's night")
        XCTAssertEqual(MorningRecord.nightDay(of: seventh.addingTimeInterval(13 * 3600), calendar: calendar), seventh, "1pm is the 7th's")
    }

    /// Night sessions join into records the morning's maths can read: the
    /// start stands as the wake, the goal is the one saved on the session,
    /// and a run past midnight lands on the evening before.
    func testJoiningNightsUsesTheStartAsTheWakeAndTheSavedGoal() {
        let sixth = calendar.startOfDay(for: at(12, 0))
        let firstNight = RoutineSession(result: SessionResult(
            startedAt: at(22, 40), endedAt: at(23, 15),
            plannedSeconds: 2400, activeSeconds: 2100, pausedSeconds: 0,
            completed: true, steps: [], kind: .night
        ), goalMinutes: 22 * 60)
        // Half past midnight: the same night, a retake, and later — ignored.
        let retake = RoutineSession(result: SessionResult(
            startedAt: sixth.addingTimeInterval(24.5 * 3600), endedAt: sixth.addingTimeInterval(25 * 3600),
            plannedSeconds: 2400, activeSeconds: 1800, pausedSeconds: 0,
            completed: true, steps: [], kind: .night
        ), goalMinutes: 22 * 60)
        let morning = RoutineSession(result: SessionResult(
            startedAt: at(6, 50), endedAt: at(7, 20),
            plannedSeconds: 1800, activeSeconds: 1800, pausedSeconds: 0,
            completed: true, steps: []
        ))

        let records = MorningRecord.joinNights(sessions: [morning, retake, firstNight], calendar: calendar)
        XCTAssertEqual(records.count, 1, "the morning is left out; the two night runs are one night")
        let night = records[0]
        XCTAssertEqual(night.day, sixth)
        XCTAssertEqual(night.wakeAt, at(22, 40))
        XCTAssertEqual(night.routineStartAt, at(22, 40))
        XCTAssertEqual(night.routineActiveSeconds, 2100)
        XCTAssertEqual(night.goalMinutes, 22 * 60)
        XCTAssertTrue(night.isComplete)
        XCTAssertEqual(night.snoozeMinutes(settings: MorningSettings(targetWakeMinutes: 21 * 60), calendar: calendar), 40, "the saved goal, not the current one")
        XCTAssertEqual(night.activationMinutes, 0)

        // Alone, the after-midnight run is the 6th's night and 150 min late.
        let late = MorningRecord.joinNights(sessions: [retake], calendar: calendar)
        XCTAssertEqual(late.map(\.day), [sixth])
        XCTAssertEqual(late[0].snoozeMinutes(settings: settings, calendar: calendar), 150)
    }

    /// The recorder stamps a night run with the night goal in force, and
    /// leaves a morning's nil — the morning's goal lives on its log.
    func testRecorderStampsNightRunsWithTheNightGoal() throws {
        let sessionContainer = try ModelContainer(
            for: RoutineSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let recorder = SessionRecorder(context: sessionContainer.mainContext, nightGoal: { 21 * 60 + 30 })
        recorder.record(SessionResult(
            startedAt: at(22, 0), endedAt: at(22, 30),
            plannedSeconds: 1800, activeSeconds: 1800, pausedSeconds: 0,
            completed: true, steps: [], kind: .night
        ))
        recorder.record(SessionResult(
            startedAt: at(6, 50), endedAt: at(7, 20),
            plannedSeconds: 1800, activeSeconds: 1800, pausedSeconds: 0,
            completed: true, steps: []
        ))

        let saved = try sessionContainer.mainContext.fetch(FetchDescriptor<RoutineSession>(sortBy: [SortDescriptor(\.startedAt)]))
        XCTAssertEqual(saved.map(\.kind), [.morning, .night])
        XCTAssertEqual(saved.map(\.goalMinutes), [nil, 21 * 60 + 30])
    }

    /// The saved kind survives the round trip through the model, and the
    /// per-routine read gives each routine only its own runs.
    func testSessionsAndStepsAreReadPerRoutine() {
        let morning = RoutineSession(result: SessionResult(
            startedAt: at(6, 50), endedAt: at(7, 20),
            plannedSeconds: 1800, activeSeconds: 1800, pausedSeconds: 0,
            completed: true, steps: []
        ))
        let night = RoutineSession(result: SessionResult(
            startedAt: at(22, 0), endedAt: at(22, 40),
            plannedSeconds: 2400, activeSeconds: 2400, pausedSeconds: 0,
            completed: true, steps: [], kind: .night
        ))
        XCTAssertEqual(morning.kind, .morning, "a result built without a kind is a morning one")
        XCTAssertEqual(night.kind, .night)
        XCTAssertEqual(night.result.kind, .night)

        let sessions = [night, morning]
        XCTAssertEqual(sessions.results(of: .morning).map(\.startedAt), [at(6, 50)])
        XCTAssertEqual(sessions.results(of: .night).map(\.startedAt), [at(22, 0)])

        let steps = [
            RoutineStep(title: "Read", durationSeconds: 900, sortOrder: 1, kind: .night),
            RoutineStep(title: "Coffee", durationSeconds: 720, sortOrder: 1),
            RoutineStep(title: "Dua", durationSeconds: 300, sortOrder: 0),
            RoutineStep(title: "Tidy", durationSeconds: 300, sortOrder: 0, kind: .night),
        ]
        XCTAssertEqual(steps[1].kind, .morning, "a step built without a kind is a morning one")
        XCTAssertEqual(steps.routine(.morning).map(\.title), ["Dua", "Coffee"])
        XCTAssertEqual(steps.routine(.night).map(\.title), ["Tidy", "Read"])
    }
}
