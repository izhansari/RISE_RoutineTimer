//
//  ProjectedScheduleTests.swift
//  RISE_RoutineTimerTests
//

import XCTest
@testable import RISE_RoutineTimer

final class ProjectedScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_757_400_000)

    private func step(_ title: String, _ seconds: Int, auto: Bool = true) -> RunStep {
        RunStep(title: title, durationSeconds: seconds, autoNext: auto)
    }

    private func result(_ step: RunStep, took: Int) -> StepResult {
        StepResult(
            stepID: step.id, title: step.title,
            plannedSeconds: step.durationSeconds, actualSeconds: took,
            autoAdvanced: false, skipped: false
        )
    }

    func testUpcomingStepsStackByTheirPlannedDurations() {
        let steps = [step("A", 60), step("B", 120), step("C", 30)]
        let schedule = ProjectedStep.project(
            steps: steps, results: [], currentIndex: 0, stepElapsed: 20, now: now
        )

        XCTAssertEqual(schedule.count, 3)
        XCTAssertEqual(schedule[0].state, .current)
        XCTAssertEqual(schedule[1].state, .upcoming)

        // The current step started 20 s ago and still ends on plan.
        XCTAssertEqual(schedule[0].start, now.addingTimeInterval(-20))
        XCTAssertEqual(schedule[0].end, now.addingTimeInterval(40))
        // Later steps butt up against it, in order.
        XCTAssertEqual(schedule[1].start, schedule[0].end)
        XCTAssertEqual(schedule[1].end, now.addingTimeInterval(160))
        XCTAssertEqual(schedule[2].end, now.addingTimeInterval(190))
    }

    func testFinishedStepsAreWalkedBackFromTheCurrentStepUsingWhatTheyTook() {
        let steps = [step("A", 60), step("B", 120), step("C", 30)]
        // B ran long: 200 s against a 120 s plan.
        let results = [result(steps[0], took: 45), result(steps[1], took: 200)]
        let schedule = ProjectedStep.project(
            steps: steps, results: results, currentIndex: 2, stepElapsed: 10, now: now
        )

        XCTAssertEqual(schedule[2].start, now.addingTimeInterval(-10))
        XCTAssertEqual(schedule[1].end, schedule[2].start)
        XCTAssertEqual(schedule[1].start, now.addingTimeInterval(-210), "200 s back from the current start")
        XCTAssertEqual(schedule[0].end, schedule[1].start)
        XCTAssertEqual(schedule[0].start, now.addingTimeInterval(-255))
        XCTAssertEqual(schedule[0].state, .done)
        XCTAssertEqual(schedule[1].seconds, 200, "the tape shows what it really took, not the plan")
        XCTAssertEqual(schedule[1].plannedSeconds, 120)
    }

    func testAStepWithNoRecordedResultFallsBackToItsPlan() {
        // Deferring a step moves it to the end and records nothing, so results
        // cannot be indexed by position.
        let steps = [step("A", 60), step("B", 120), step("C", 30)]
        let results = [result(steps[1], took: 100)]
        let schedule = ProjectedStep.project(
            steps: steps, results: results, currentIndex: 2, stepElapsed: 0, now: now
        )

        XCTAssertEqual(schedule[1].seconds, 100, "matched by id, not position")
        XCTAssertEqual(schedule[0].seconds, 60, "no result, so the plan stands in")
    }

    func testOvertimeHoldsTheCurrentStepAtNowSoLaterStepsDoNotStartInThePast() {
        let steps = [step("A", 60, auto: false), step("B", 120)]
        let schedule = ProjectedStep.project(
            steps: steps, results: [], currentIndex: 0, stepElapsed: 300, now: now
        )

        XCTAssertEqual(schedule[0].start, now.addingTimeInterval(-300))
        XCTAssertEqual(schedule[0].end, now, "four minutes over, so it ends now — not four minutes ago")
        XCTAssertEqual(schedule[1].start, now)
        XCTAssertEqual(schedule[1].end, now.addingTimeInterval(120))
    }

    func testTheLastEndMatchesTheEnginesProjectedEnd() {
        // The tape and the bottom bar's DONE AT must never disagree.
        let steps = [step("A", 60), step("B", 120), step("C", 30)]
        let elapsed: TimeInterval = 25
        let schedule = ProjectedStep.project(
            steps: steps, results: [], currentIndex: 0, stepElapsed: elapsed, now: now
        )

        let remaining = Int(max(0, 60 - elapsed).rounded(.up)) + 120 + 30
        XCTAssertEqual(schedule.last?.end, now.addingTimeInterval(TimeInterval(remaining)))
    }

    func testEmptyAndOutOfRangeRunsProjectNothing() {
        XCTAssertTrue(ProjectedStep.project(steps: [], results: [], currentIndex: 0, stepElapsed: 0, now: now).isEmpty)
        XCTAssertTrue(ProjectedStep.project(steps: [step("A", 60)], results: [], currentIndex: 4, stepElapsed: 0, now: now).isEmpty)
    }
}
