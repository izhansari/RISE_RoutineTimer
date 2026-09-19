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

    // MARK: - Correcting a past run

    private func session(_ steps: [StepResult]) -> SessionResult {
        let start = Date(timeIntervalSince1970: 1_758_000_000)
        let active = steps.reduce(0) { $0 + $1.actualSeconds }
        return SessionResult(
            startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(active + 30)),
            plannedSeconds: steps.reduce(0) { $0 + $1.plannedSeconds },
            activeSeconds: active, pausedSeconds: 30, completed: true, steps: steps
        )
    }

    func testCorrectingAForgottenLastStepPullsTheEndBackIn() {
        // Coffee left running for two hours after the routine was really over.
        let run = session([step(300, 280), step(720, 7_200)])
        let fixed = run.correcting(stepAt: 1, toSeconds: 660)

        XCTAssertEqual(fixed.steps[1].actualSeconds, 660)
        XCTAssertEqual(fixed.activeSeconds, 940)
        XCTAssertEqual(fixed.endedAt, run.endedAt.addingTimeInterval(-6_540), "the end moves by exactly the correction")
        XCTAssertEqual(fixed.startedAt, run.startedAt, "the start was recorded right and stays")
        XCTAssertEqual(fixed.pausedSeconds, 30, "pauses are untouched")
        XCTAssertEqual(fixed.steps[1].outcome, .under)
        XCTAssertEqual(fixed.steps[0], run.steps[0], "other steps are untouched")
    }

    func testACorrectedAutoStepIsJudgedByItsNewTime() {
        let run = session([step(60, 60, auto: true)])
        let fixed = run.correcting(stepAt: 0, toSeconds: 90)

        XCTAssertFalse(fixed.steps[0].autoAdvanced)
        XCTAssertEqual(fixed.steps[0].outcome, .over)
    }

    func testCorrectingIsANoOpForTheSameTimeOrABadIndex() {
        let run = session([step(60, 70)])
        XCTAssertEqual(run.correcting(stepAt: 0, toSeconds: 70), run)
        XCTAssertEqual(run.correcting(stepAt: 3, toSeconds: 10), run)
        XCTAssertEqual(run.correcting(stepAt: 0, toSeconds: -5).steps[0].actualSeconds, 0, "clamped at zero")
    }

    // MARK: - Where the time went

    func testCompositionSharesAddUpAndStackInRunOrder() {
        let ring = RunComposition(steps: [step(300, 300), step(60, 100), step(600, 600)])

        XCTAssertEqual(ring.totalSeconds, 1000)
        XCTAssertEqual(ring.slices.map(\.startSeconds), [0, 300, 400])
        XCTAssertEqual(ring.slices.map(\.share), [0.3, 0.1, 0.6])
        XCTAssertEqual(ring.slices.reduce(0) { $0 + $1.share }, 1, accuracy: 0.0001)
        XCTAssertEqual(ring.slices[1].outcome, .over, "each slice carries how its step went")
        XCTAssertEqual(ring.largestIndex, 2)
    }

    func testATouchOnTheRingFindsItsStep() {
        let ring = RunComposition(steps: [step(300, 300), step(60, 100), step(600, 600)])

        XCTAssertEqual(ring.index(atSeconds: 0), 0)
        XCTAssertEqual(ring.index(atSeconds: 299.9), 0)
        XCTAssertEqual(ring.index(atSeconds: 300), 1, "a boundary belongs to the step that starts there")
        XCTAssertEqual(ring.index(atSeconds: 399.9), 1)
        XCTAssertEqual(ring.index(atSeconds: 400), 2)
        XCTAssertEqual(ring.index(atSeconds: 1000), 2, "the far end clamps to the last step")
        XCTAssertEqual(ring.index(atSeconds: -4), 0)
    }

    /// A step skipped the instant it appeared has no width, so it can be
    /// neither under a finger nor where the ring opens.
    func testStepsThatTookNoTimeAreNeverSelected() {
        let ring = RunComposition(steps: [step(60, 0, skipped: true), step(60, 50), step(60, 0, skipped: true), step(60, 50)])

        XCTAssertEqual(ring.index(atSeconds: 0), 1)
        XCTAssertEqual(ring.index(atSeconds: 50), 3, "the empty step at the boundary is passed over")
        XCTAssertEqual(ring.index(atSeconds: 500), 3)
        XCTAssertEqual(ring.largestIndex, 1, "the earlier step on a tie")
        XCTAssertEqual(ring.slices[0].share, 0)
    }

    /// Four equal steps: one per quadrant, clockwise from twelve.
    func testATapOnTheRingIsReadClockwiseFromTwelve() {
        let ring = RunComposition(steps: [step(60, 60), step(60, 60), step(60, 60), step(60, 60)])
        let size = CGSize(width: 200, height: 200)
        func tap(_ x: Double, _ y: Double) -> Int? {
            ring.index(at: CGPoint(x: x, y: y), inRingOf: size, innerRatio: 0.6)
        }

        XCTAssertEqual(tap(160, 40), 0, "upper right")
        XCTAssertEqual(tap(160, 160), 1, "lower right")
        XCTAssertEqual(tap(40, 160), 2, "lower left")
        XCTAssertEqual(tap(40, 40), 3, "upper left")
        XCTAssertEqual(tap(101, 10), 0, "just past twelve")
        XCTAssertEqual(tap(99, 10), 3, "just before it")

        XCTAssertNil(tap(100, 100), "the hole holds the readout")
        XCTAssertNil(tap(130, 100), "still inside the hole")
        XCTAssertNil(tap(2, 2), "the corner of the square is outside the ring")
    }

    func testAnEmptyRunHasNoRing() {
        XCTAssertNil(RunComposition(steps: []).largestIndex)
        XCTAssertNil(RunComposition(steps: []).index(atSeconds: 10))

        let nothingHappened = RunComposition(steps: [step(60, 0, skipped: true)])
        XCTAssertEqual(nothingHappened.totalSeconds, 0)
        XCTAssertNil(nothingHappened.largestIndex)
        XCTAssertNil(nothingHappened.index(atSeconds: 0))
        XCTAssertEqual(nothingHappened.slices[0].share, 0, "no division by zero")
    }
}
