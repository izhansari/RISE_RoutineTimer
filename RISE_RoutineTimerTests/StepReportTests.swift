//
//  StepReportTests.swift
//  RISE_RoutineTimerTests
//

import XCTest
@testable import RISE_RoutineTimer

final class StepReportTests: XCTestCase {
    private let step = UUID()
    private let before = UUID()
    private let day0 = Date(timeIntervalSince1970: 1_757_000_000)

    private func result(_ id: UUID, planned: Int, actual: Int, auto: Bool = false, skipped: Bool? = nil) -> StepResult {
        StepResult(stepID: id, title: "Step", plannedSeconds: planned, actualSeconds: actual, autoAdvanced: auto, skipped: skipped)
    }

    /// A morning where a 60-second step runs before the one under test.
    private func run(_ day: Int, actual: Int, planned: Int = 240, auto: Bool = false, skipped: Bool? = nil, completed: Bool = true) -> SessionResult {
        let steps = [
            result(before, planned: 60, actual: 60),
            result(step, planned: planned, actual: actual, auto: auto, skipped: skipped),
        ]
        let start = day0.addingTimeInterval(TimeInterval(day) * 86_400)
        let active = steps.reduce(0) { $0 + $1.actualSeconds }
        return SessionResult(
            startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(active)),
            plannedSeconds: 300, activeSeconds: active, pausedSeconds: 0,
            completed: completed, steps: steps
        )
    }

    private func report(_ sessions: [SessionResult]) -> StepReport {
        StepReport(stepID: step, plannedSeconds: 240, sessions: sessions)
    }

    func testRunsAreMatchedByIDOldestFirstWithWhereTheyStarted() {
        let r = report([run(2, actual: 250), run(0, actual: 230), run(1, actual: 240, completed: false)])

        XCTAssertEqual(r.runs.map(\.result.actualSeconds), [230, 250], "oldest first; abandoned runs left out")
        XCTAssertEqual(r.runs.first?.startOffsetSeconds, 60, "starts after the step before it")
        XCTAssertEqual(r.runs.first?.shareOfRoutine ?? 0, 230.0 / 290.0, accuracy: 0.0001)
    }

    func testTypicalIsTheMedianAndTheUsualRangeTheMiddleHalf() {
        let r = report([260, 200, 400, 240, 220].enumerated().map { run($0.offset, actual: $0.element) })

        XCTAssertEqual(r.typicalSeconds, 240, "one slow morning doesn't move a median")
        XCTAssertEqual(r.usualRange, 220...260)
        XCTAssertEqual(r.best?.result.actualSeconds, 200)
        XCTAssertEqual(r.slowest?.result.actualSeconds, 400)
        XCTAssertEqual(r.count(.over), 2)
        XCTAssertEqual(r.count(.under), 2)
        XCTAssertEqual(r.count(.onPlan), 1)
    }

    func testRunsThatBarelyHappenedOrWereAutoAreCountedButNotTimed() {
        let r = report([
            run(0, actual: 250),
            run(1, actual: 30),                  // cut short: under a quarter of plan
            run(2, actual: 100, skipped: true),
            run(3, actual: 240, auto: true),
            run(4, actual: 230),
        ])

        XCTAssertEqual(r.runs.count, 5)
        XCTAssertEqual(r.timed.map(\.result.actualSeconds), [250, 230])
        XCTAssertEqual(r.count(.cutShort), 1)
        XCTAssertEqual(r.count(.skipped), 1)
        XCTAssertEqual(r.count(.auto), 1)
        XCTAssertEqual(r.finishedCount, 3)
        XCTAssertEqual(r.typicalSeconds, 240, "median of 250 and 230")
        XCTAssertNil(r.usualRange, "needs four timed runs")
        XCTAssertFalse(r.isAutoOnly)
    }

    func testTrendComparesRecentRunsWithTheOnesBefore() {
        let r = report([300, 310, 290, 240, 250, 230].enumerated().map { run($0.offset, actual: $0.element) })
        XCTAssertEqual(r.trendSeconds, -60, "a minute faster than the three runs before")

        XCTAssertNil(report([run(0, actual: 300), run(1, actual: 240)]).trendSeconds,
                     "needs at least three timed runs either side")
    }

    func testAnAutoOnlyStepHasNothingToTime() {
        let r = report([run(0, actual: 240, auto: true), run(1, actual: 240, auto: true)])

        XCTAssertTrue(r.isAutoOnly)
        XCTAssertNil(r.typicalSeconds)
        XCTAssertNil(r.best)
        XCTAssertEqual(r.typicalStartOffsetSeconds, 60)
    }

    func testOnlyTheMostRecentWindowIsKept() {
        let sessions = (0..<(StepReport.window + 5)).map { run($0, actual: 240) }
        let r = report(sessions)

        XCTAssertEqual(r.runs.count, StepReport.window)
        XCTAssertEqual(r.runs.first?.sessionStart, sessions[5].startedAt)
    }

    func testPercentileInterpolatesBetweenValues() {
        XCTAssertEqual(StepReport.percentile([10, 20], 0.5), 15)
        XCTAssertEqual(StepReport.percentile([5], 0.75), 5)
        XCTAssertEqual(StepReport.percentile([], 0.5), 0)
    }
}
