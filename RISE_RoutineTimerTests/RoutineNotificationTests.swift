//
//  RoutineNotificationTests.swift
//  RISE_RoutineTimerTests
//
//  Runs against the simulator's real notification centre (the tests are
//  hosted in the app), because the bug this pins was an ordering problem
//  between the app and that centre, not a logic error a fake would show.
//

import UserNotifications
import XCTest
@testable import RISE_RoutineTimer

@MainActor
final class RoutineNotificationTests: XCTestCase {
    private let steps = [
        RunStep(title: "Shampoo", durationSeconds: 75),
        RunStep(title: "Face wash", durationSeconds: 75),
        RunStep(title: "Body wash", durationSeconds: 75),
    ]

    private func pendingRunAlerts() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("rise-run-") }
    }

    override func tearDown() async throws {
        RoutineNotificationManager.cancelRunAlerts()
        await RoutineNotificationManager.settle()
    }

    /// A chain of auto steps is scheduled whole, so when the next step starts
    /// the new plan covers steps the old plan already had alerts for.
    /// Rescheduling must leave the new alerts standing.
    func testReschedulingAnAutoChainKeepsTheNewAlerts() async throws {
        let start = Date()
        let engine = RoutineEngine(store: nil, usesWallClock: false, now: start)
        engine.start(steps: steps, at: start)

        RoutineNotificationManager.schedule(engine.plannedAlerts(at: start), steps: steps, now: start)
        await RoutineNotificationManager.settle()
        let first = await pendingRunAlerts()
        XCTAssertEqual(first.count, 4, "three step ends and the completion")

        // The second step begins ten seconds later than the first plan was made.
        let later = start.addingTimeInterval(10)
        engine.completeCurrentStep(at: later)
        RoutineNotificationManager.schedule(engine.plannedAlerts(at: later), steps: steps, now: later)
        await RoutineNotificationManager.settle()

        let second = await pendingRunAlerts()
        XCTAssertEqual(second.count, 3, "two step ends and the completion survive the reschedule")
    }

    /// Calls made back to back, without waiting, land in the order they were
    /// made: the last plan wins, and a cancel after it leaves nothing.
    func testBackToBackCallsApplyInOrder() async {
        let start = Date()
        let engine = RoutineEngine(store: nil, usesWallClock: false, now: start)
        engine.start(steps: steps, at: start)
        let plan = engine.plannedAlerts(at: start)

        RoutineNotificationManager.schedule(plan, steps: steps, now: start)
        RoutineNotificationManager.schedule(plan, steps: steps, now: start)
        await RoutineNotificationManager.settle()
        let afterTwo = await pendingRunAlerts()
        XCTAssertEqual(afterTwo.count, plan.count, "one plan's worth, not two and not none")

        RoutineNotificationManager.schedule(plan, steps: steps, now: start)
        RoutineNotificationManager.cancelRunAlerts()
        await RoutineNotificationManager.settle()
        let afterCancel = await pendingRunAlerts()
        XCTAssertTrue(afterCancel.isEmpty)
    }
}
