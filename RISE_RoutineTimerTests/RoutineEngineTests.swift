//
//  RoutineEngineTests.swift
//  RISE_RoutineTimerTests
//
//  The engine is driven with synthetic dates so every scenario is deterministic.
//

import XCTest
@testable import RISE_RoutineTimer

final class RoutineEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func makeSteps() -> [RunStep] {
        [
            RunStep(title: "Water", durationSeconds: 120, autoNext: true),
            RunStep(title: "Stretch", durationSeconds: 300, autoNext: true),
            RunStep(title: "Wash", durationSeconds: 600, autoNext: false),
            RunStep(title: "Plan", durationSeconds: 300, autoNext: true),
        ]
    }

    private func makeEngine(store: RunStore? = nil) -> (RoutineEngine, [RoutineEngine.Event]) {
        let engine = RoutineEngine(store: store, usesWallClock: false, now: t0)
        return (engine, [])
    }

    private func startedEngine(store: RunStore? = nil) -> (RoutineEngine, EventLog) {
        let engine = RoutineEngine(store: store, usesWallClock: false, now: t0)
        let log = EventLog()
        engine.onEvent = { log.events.append($0) }
        engine.start(steps: makeSteps(), at: t0)
        return (engine, log)
    }

    final class EventLog { var events: [RoutineEngine.Event] = [] }

    // MARK: - Starting

    func testStartBeginsFirstStepWithFullDuration() {
        let (engine, log) = startedEngine()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.secondsRemaining, 120)
        XCTAssertEqual(engine.plannedTotalSeconds, 1320)
        XCTAssertEqual(engine.projectedEndDate, at(1320))
        XCTAssertEqual(engine.scheduleDeltaSeconds, 0)
        XCTAssertEqual(log.events, [.started, .stepStarted(index: 0, auto: false)])
    }

    func testStartWithNoStepsDoesNothing() {
        let (engine, _) = makeEngine()
        engine.start(steps: [], at: t0)
        XCTAssertNil(engine.run)
    }

    // MARK: - Countdown and auto-advance

    func testCountdownRoundsUpUntilTheSecondHasFullyPassed() {
        let (engine, _) = startedEngine()
        engine.tick(at: at(0.4))
        XCTAssertEqual(engine.secondsRemaining, 120)
        engine.tick(at: at(1.0))
        XCTAssertEqual(engine.secondsRemaining, 119)
        engine.tick(at: at(119.5))
        XCTAssertEqual(engine.secondsRemaining, 1)
        XCTAssertEqual(engine.currentStepFillProgress, 119.5 / 120, accuracy: 0.0001)
    }

    func testAutoNextStepAdvancesAndCarriesOverflow() {
        let (engine, log) = startedEngine()
        engine.tick(at: at(121.5))

        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.stepElapsed, 1.5, accuracy: 0.0001)
        XCTAssertEqual(engine.results.count, 1)
        XCTAssertEqual(engine.results[0].actualSeconds, 120)
        XCTAssertTrue(engine.results[0].autoAdvanced)
        XCTAssertEqual(engine.scheduleDeltaSeconds, 0)
        XCTAssertEqual(log.events.last, .stepStarted(index: 1, auto: true))
    }

    func testBackgroundCatchUpAdvancesThroughAChainButEmitsOnce() {
        let (engine, log) = startedEngine()
        log.events.removeAll()
        // Water (120) + Stretch (300) both expire; Wash is manual so we stop there, 10s into it.
        engine.tick(at: at(430))

        XCTAssertEqual(engine.currentIndex, 2)
        XCTAssertEqual(engine.stepElapsed, 10, accuracy: 0.0001)
        XCTAssertEqual(engine.results.map(\.actualSeconds), [120, 300])
        XCTAssertEqual(log.events, [.stepStarted(index: 2, auto: true)])
    }

    func testAutoNextLastStepCompletesRoutineAtScheduledMoment() {
        let steps = [
            RunStep(title: "A", durationSeconds: 60, autoNext: true),
            RunStep(title: "B", durationSeconds: 60, autoNext: true),
        ]
        let engine = RoutineEngine(store: nil, usesWallClock: false, now: t0)
        let log = EventLog()
        engine.onEvent = { log.events.append($0) }
        engine.start(steps: steps, at: t0)
        engine.tick(at: at(125))

        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.run?.endedAt, at(120))
        XCTAssertEqual(engine.activeElapsedSeconds, 120)
        guard case .completed(let result)? = log.events.last else {
            return XCTFail("Expected a completed event, got \(log.events)")
        }
        XCTAssertTrue(result.completed)
        XCTAssertEqual(result.activeSeconds, 120)
        XCTAssertEqual(result.endedAt, at(120))
    }

    // MARK: - Manual steps and overtime

    func testManualStepStallsInOvertimeAndAnnouncesOnce() {
        let (engine, log) = startedEngine()
        engine.tick(at: at(420))            // 0s into Wash
        log.events.removeAll()

        engine.tick(at: at(1020))           // exactly at the end of Wash
        XCTAssertEqual(engine.currentIndex, 2)
        XCTAssertTrue(engine.isOvertime)
        XCTAssertEqual(engine.overtimeSeconds, 0)
        XCTAssertEqual(log.events, [.overtimeStarted(index: 2)])

        engine.tick(at: at(1080))           // 60s over
        XCTAssertEqual(engine.overtimeSeconds, 60)
        XCTAssertEqual(engine.secondsRemaining, -60)
        XCTAssertEqual(engine.scheduleDeltaSeconds, 60)
        XCTAssertEqual(engine.projectedEndDate, at(1080 + 300), "end time extends while stalled")
        XCTAssertEqual(log.events.count, 1, "overtime is announced only once")
    }

    func testFinishingEarlyPullsTheEndTimeForward() {
        let (engine, _) = startedEngine()
        engine.completeCurrentStep(at: at(30))   // Water done 90s early

        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.results[0].actualSeconds, 30)
        XCTAssertEqual(engine.scheduleDeltaSeconds, -90)
        XCTAssertEqual(engine.projectedEndDate, at(30 + 300 + 600 + 300))
        XCTAssertEqual(engine.stepStartDate, at(30))
    }

    func testCompletingTheLastStepManuallyFinishesWithOvertimeIncluded() {
        let steps = [RunStep(title: "Only", durationSeconds: 60, autoNext: false)]
        let engine = RoutineEngine(store: nil, usesWallClock: false, now: t0)
        var result: SessionResult?
        engine.onEvent = { if case .completed(let r) = $0 { result = r } }
        engine.start(steps: steps, at: t0)
        engine.tick(at: at(90))
        engine.completeCurrentStep(at: at(90))

        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(result?.activeSeconds, 90)
        XCTAssertEqual(result?.deltaSeconds, 30)
        XCTAssertEqual(engine.scheduleDeltaSeconds, 30)
        XCTAssertEqual(engine.projectedEndDate, at(90))
    }

    // MARK: - Pause and resume

    func testPauseFreezesTheClockAndKeepsTheOriginalStartTime() {
        let (engine, _) = startedEngine()
        engine.tick(at: at(50))
        engine.pause(at: at(50))
        XCTAssertTrue(engine.isPaused)

        engine.tick(at: at(200))
        XCTAssertEqual(engine.secondsRemaining, 70, "no time passes while paused")
        XCTAssertEqual(engine.pausedSeconds, 150)

        engine.resume(at: at(200))
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.routineStartDate, t0, "start time is the real start, not shifted by the pause")
        engine.tick(at: at(210))
        XCTAssertEqual(engine.secondsRemaining, 60)
        XCTAssertEqual(engine.stepStartDate, at(150), "step start is shown as if the pause never happened")
        XCTAssertEqual(engine.pausedSeconds, 150)
    }

    func testPausedTimeDoesNotTriggerAutoAdvance() {
        let (engine, _) = startedEngine()
        engine.pause(at: at(10))
        engine.tick(at: at(10_000))
        XCTAssertEqual(engine.currentIndex, 0)
        engine.resume(at: at(10_000))
        engine.tick(at: at(10_000 + 109))
        XCTAssertEqual(engine.currentIndex, 0)
        engine.tick(at: at(10_000 + 110))
        XCTAssertEqual(engine.currentIndex, 1)
    }

    // MARK: - Plan progress

    // Steps: Water 120, Stretch 300, Wash 600 (manual), Plan 300 → 1320 s.

    func testPlanProgressJumpsToTheBoundaryWhenAStepFinishesEarly() {
        let (engine, _) = startedEngine()
        engine.tick(at: at(30))
        XCTAssertEqual(engine.routinePlanProgress, 30.0 / 1320, accuracy: 0.0001)

        engine.completeCurrentStep(at: at(30))
        // The whole 120 s of Water now counts, not the 30 s it actually took.
        XCTAssertEqual(engine.routinePlanProgress, 120.0 / 1320, accuracy: 0.0001)
    }

    func testPlanProgressHoldsAtTheBoundaryInOvertime() {
        let (engine, _) = startedEngine()
        engine.completeCurrentStep(at: at(10))
        engine.completeCurrentStep(at: at(20))
        engine.tick(at: at(20 + 700))   // Wash is 600 s; 100 s over
        XCTAssertEqual(engine.routinePlanProgress, (120.0 + 300 + 600) / 1320, accuracy: 0.0001)
    }

    func testPlanProgressIsCompleteAtTheEnd() {
        let (engine, _) = startedEngine()
        for _ in 0..<4 { engine.completeCurrentStep(at: at(10)) }
        XCTAssertEqual(engine.routinePlanProgress, 1, accuracy: 0.0001)
    }

    // MARK: - Skip and defer

    func testSkipRecordsTheStepAsSkippedAndMovesOn() {
        let (engine, log) = startedEngine()
        engine.tick(at: at(30))
        engine.skipCurrentStep(at: at(30))

        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.results.count, 1)
        XCTAssertTrue(engine.results[0].wasSkipped)
        // The time actually spent still counts, so the session total is honest.
        XCTAssertEqual(engine.results[0].actualSeconds, 30)
        XCTAssertEqual(log.events.last, .stepStarted(index: 1, auto: false))
    }

    func testSkippingTheLastStepFinishesTheRoutine() {
        let (engine, _) = startedEngine()
        engine.completeCurrentStep(at: at(10))
        engine.completeCurrentStep(at: at(20))
        engine.completeCurrentStep(at: at(30))
        XCTAssertEqual(engine.currentIndex, 3)

        engine.skipCurrentStep(at: at(40))
        XCTAssertTrue(engine.isComplete)
        XCTAssertTrue(engine.results.last?.wasSkipped == true)
    }

    func testSkippedStepCountsAsAheadOfPlan() {
        let (engine, _) = startedEngine()
        engine.skipCurrentStep(at: at(0))
        // A 120 s step skipped instantly is 120 s ahead.
        XCTAssertEqual(engine.scheduleDeltaSeconds, -120)
    }

    func testMoveToEndReordersAndStartsTheFollowingStep() {
        let (engine, log) = startedEngine()
        engine.tick(at: at(20))
        engine.moveCurrentStepToEnd(at: at(20))

        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.currentStep?.title, "Stretch")
        XCTAssertEqual(engine.steps.map(\.title), ["Stretch", "Wash", "Plan", "Water"])
        // Deferring is not doing: nothing is recorded for the moved step.
        XCTAssertTrue(engine.results.isEmpty)
        XCTAssertEqual(engine.stepElapsed, 0, accuracy: 0.0001)
        XCTAssertEqual(log.events.last, .stepStarted(index: 0, auto: false))
    }

    func testMoveToEndKeepsThePlannedTotal() {
        let (engine, _) = startedEngine()
        let planned = engine.plannedTotalSeconds
        engine.moveCurrentStepToEnd(at: at(20))
        XCTAssertEqual(engine.plannedTotalSeconds, planned)
    }

    func testMoveToEndOnTheLastStepDoesNothing() {
        let (engine, _) = startedEngine()
        engine.completeCurrentStep(at: at(10))
        engine.completeCurrentStep(at: at(20))
        engine.completeCurrentStep(at: at(30))
        let order = engine.steps.map(\.title)

        engine.moveCurrentStepToEnd(at: at(40))
        XCTAssertEqual(engine.currentIndex, 3)
        XCTAssertEqual(engine.steps.map(\.title), order)
    }

    // MARK: - Editing notes mid-run

    func testUpdateNotesWritesIntoTheFrozenRun() {
        let (engine, _) = startedEngine()
        let id = engine.currentStep!.id
        engine.updateNotes("Remember the vitamins", forStepID: id)
        XCTAssertEqual(engine.currentStep?.notes, "Remember the vitamins")
        XCTAssertTrue(engine.currentStep?.hasNotes == true)
    }

    func testUpdateNotesIgnoresAnUnknownStep() {
        let (engine, _) = startedEngine()
        engine.updateNotes("nope", forStepID: UUID())
        XCTAssertEqual(engine.currentStep?.notes, "")
    }

    // MARK: - Abandon and reset

    func testAbandonProducesAnIncompleteResultAndClearsTheRun() {
        let (engine, log) = startedEngine()
        engine.completeCurrentStep(at: at(100))
        engine.pause(at: at(160))
        engine.abandon(at: at(200))

        XCTAssertNil(engine.run)
        guard case .abandoned(let result)? = log.events.last else {
            return XCTFail("Expected abandoned event")
        }
        XCTAssertFalse(result.completed)
        XCTAssertEqual(result.activeSeconds, 160)
        XCTAssertEqual(result.pausedSeconds, 40)
        XCTAssertEqual(result.steps.count, 1)
    }

    // MARK: - Persistence

    func testRunningRunSurvivesRelaunchAndCatchesUp() {
        let store = InMemoryRunStore()
        let (engine, _) = startedEngine(store: store)
        engine.tick(at: at(30))
        XCTAssertNotNil(store.stored)

        let relaunched = RoutineEngine(store: store, usesWallClock: false, now: at(200))
        XCTAssertTrue(relaunched.isRunning)
        relaunched.tick(at: at(200))
        XCTAssertEqual(relaunched.currentIndex, 1, "expired auto step is completed on relaunch")
        XCTAssertEqual(relaunched.routineStartDate, t0)
    }

    func testPausedRunSurvivesRelaunch() {
        let store = InMemoryRunStore()
        let (engine, _) = startedEngine(store: store)
        engine.pause(at: at(45))

        let relaunched = RoutineEngine(store: store, usesWallClock: false, now: at(3600))
        XCTAssertTrue(relaunched.isPaused)
        XCTAssertEqual(relaunched.secondsRemaining, 75)
    }

    func testStaleAndCompletedRunsAreDroppedOnRelaunch() {
        let store = InMemoryRunStore()
        let (engine, _) = startedEngine(store: store)
        engine.pause(at: at(45))
        let stale = RoutineEngine(store: store, usesWallClock: false, now: at(13 * 3600))
        XCTAssertNil(stale.run)
        XCTAssertNil(store.stored)

        let (finished, _) = startedEngine(store: store)
        for _ in 0..<4 { finished.completeCurrentStep(at: at(10)) }
        XCTAssertTrue(finished.isComplete)
        let afterComplete = RoutineEngine(store: store, usesWallClock: false, now: at(20))
        XCTAssertNil(afterComplete.run)
    }

    func testRunRoundTripsThroughJSON() throws {
        let (engine, _) = startedEngine()
        engine.completeCurrentStep(at: at(30))
        let run = try XCTUnwrap(engine.run)
        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(RoutineRun.self, from: data)
        XCTAssertEqual(decoded, run)
    }

    // MARK: - Notification planning

    func testPlannedAlertsFollowAutoChainAndStopAtManualStep() {
        let (engine, _) = startedEngine()
        let alerts = engine.plannedAlerts(at: t0)

        XCTAssertEqual(alerts.map(\.kind), [
            .stepEnd, .stepEnd, .stepEnd,
            .overtime(minutes: 1), .overtime(minutes: 3), .overtime(minutes: 5), .overtime(minutes: 10),
        ])
        XCTAssertEqual(alerts.map(\.stepIndex), [0, 1, 2, 2, 2, 2, 2])
        XCTAssertEqual(alerts[0].fireDate, at(120))
        XCTAssertEqual(alerts[1].fireDate, at(420))
        XCTAssertEqual(alerts[2].fireDate, at(1020))
        XCTAssertEqual(alerts[3].fireDate, at(1080))
    }

    func testPlannedAlertsSkipPastMomentsAndIncludeCompletion() {
        let (engine, _) = startedEngine()
        engine.tick(at: at(1050))                        // 30s into overtime on Wash
        var alerts = engine.plannedAlerts(at: at(1050))
        XCTAssertEqual(alerts.map(\.kind), [
            .overtime(minutes: 1), .overtime(minutes: 3), .overtime(minutes: 5), .overtime(minutes: 10),
        ])

        engine.completeCurrentStep(at: at(1050))         // on to Plan, the auto-next last step
        alerts = engine.plannedAlerts(at: at(1050))
        XCTAssertEqual(alerts.map(\.kind), [.stepEnd, .completion])
        XCTAssertEqual(alerts[1].fireDate, at(1350))
    }

    func testNoAlertsWhilePaused() {
        let (engine, _) = startedEngine()
        engine.pause(at: at(10))
        XCTAssertTrue(engine.plannedAlerts(at: at(10)).isEmpty)
    }

    // MARK: - Formatting helpers used by alerts

    func testSpokenDuration() {
        XCTAssertEqual(TimeFormatting.spokenDuration(from: 300), "5 minutes")
        XCTAssertEqual(TimeFormatting.spokenDuration(from: 90), "1 minute 30 seconds")
        XCTAssertEqual(TimeFormatting.spokenDuration(from: 45), "45 seconds")
        XCTAssertEqual(TimeFormatting.spokenDuration(from: 0), "0 seconds")
    }

    func testScheduleDeltaText() {
        XCTAssertEqual(TimeFormatting.scheduleDeltaText(from: 0), "ON PLAN")
        XCTAssertEqual(TimeFormatting.scheduleDeltaText(from: -90), "1:30 AHEAD")
        XCTAssertEqual(TimeFormatting.scheduleDeltaText(from: 45), "0:45 BEHIND")
    }
}
