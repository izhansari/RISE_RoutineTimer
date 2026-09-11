//
//  SessionBreakdownTests.swift
//  RISE_RoutineTimerTests
//

import XCTest
@testable import RISE_RoutineTimer

final class SessionBreakdownTests: XCTestCase {
    private func step(_ planned: Int, _ actual: Int, auto: Bool = false, skipped: Bool? = nil) -> StepResult {
        StepResult(
            stepID: UUID(), title: "Step",
            plannedSeconds: planned, actualSeconds: actual,
            autoAdvanced: auto, skipped: skipped
        )
    }

    func testOutcomeThresholds() {
        XCTAssertEqual(step(60, 64).outcome, .over)
        XCTAssertEqual(step(60, 63).outcome, .onPlan, "three seconds either side is on plan")
        XCTAssertEqual(step(60, 57).outcome, .onPlan)
        XCTAssertEqual(step(60, 56).outcome, .under)
        XCTAssertEqual(step(300, 74).outcome, .cutShort, "under a quarter of plan")
        XCTAssertEqual(step(300, 75).outcome, .under, "exactly a quarter is merely quick")
    }

    func testSkippedAndAutoWinOverTiming() {
        XCTAssertEqual(step(300, 5, skipped: true).outcome, .skipped)
        XCTAssertEqual(step(60, 60, auto: true).outcome, .auto)
        XCTAssertEqual(step(60, 35, auto: true).outcome, .under, "an auto step whose times say it deviated is judged by them")
        XCTAssertEqual(step(60, 1, skipped: false).outcome, .cutShort, "an explicit false is not a skip")
        XCTAssertTrue(StepOutcome.cutShort.barelyHappened)
        XCTAssertTrue(StepOutcome.skipped.barelyHappened)
        XCTAssertFalse(StepOutcome.under.barelyHappened)
    }

    func testShareOfPlan() {
        XCTAssertEqual(step(225, 270).shareOfPlan, 0.2, accuracy: 0.0001)
        XCTAssertEqual(step(240, 156).shareOfPlan, -0.35, accuracy: 0.0001)
        XCTAssertEqual(step(0, 10).shareOfPlan, 0, "a zero-length plan has no share")
    }

    func testConsecutiveAutoStepsFoldButALoneOneDoesNot() {
        let steps = [
            step(60, 60),
            step(60, 60, auto: true), step(60, 60, auto: true), step(60, 60, auto: true),
            step(60, 70),
            step(60, 60, auto: true),
        ]
        let rows = SessionBreakdown(steps: steps).rows

        XCTAssertEqual(rows.map(\.id), [0, 1, 4, 5])
        guard case .autoRun(let first, let run) = rows[1] else { return XCTFail("expected a folded auto run") }
        XCTAssertEqual(first, 1)
        XCTAssertEqual(run.count, 3)
        guard case .step(let index, _, let outcome) = rows[3] else { return XCTFail("a lone auto step stays a step") }
        XCTAssertEqual(index, 5)
        XCTAssertEqual(outcome, .auto)
    }

    func testPaceLeavesOutStepsThatBarelyHappened() {
        // The 10 Sep 1:13 PM run, as recorded on the phone. It reported
        // "17:28 ahead"; the twelve steps that really ran were 0:20 under.
        let steps = [
            step(300, 17), step(60, 1), step(60, 60), step(75, 75), step(225, 270),
            step(105, 105, auto: true), step(60, 60, auto: true), step(75, 75, auto: true),
            step(75, 75, auto: true), step(75, 75, auto: true),
            step(80, 86), step(240, 156), step(195, 177), step(300, 331), step(720, 34),
        ]
        let breakdown = SessionBreakdown(steps: steps)

        XCTAssertEqual(breakdown.pacedStepCount, 12)
        XCTAssertEqual(breakdown.pacedDeltaSeconds, -20)
        XCTAssertEqual(breakdown.barelyHappenedCount, 3)
        XCTAssertEqual(breakdown.barelyHappenedDeltaSeconds, -1028)
        XCTAssertEqual(breakdown.rows.count, 11, "fifteen steps, the five auto steps as one row")
    }
}
