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
        RoutineNotificationManager.scheduleNightReminder(atMinutesAfterMidnight: nil)
        await RoutineNotificationManager.settle()
    }

    /// With nothing saved — the owner's phone, which had never touched the
    /// switch — the reminder is on, at the stored goal. Switched off, it is
    /// removed.
    func testNightReminderIsOnUnlessSwitchedOff() async throws {
        let suite = "rise-night-reminder-test"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(23 * 60, forKey: NightSettings.targetStartKey)

        XCTAssertTrue(NightSettings.storedReminderEnabled(in: defaults))
        RoutineNotificationManager.syncNightReminder(defaults: defaults)
        await RoutineNotificationManager.settle()
        var pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .first { $0.identifier == RoutineNotificationManager.nightReminderIdentifier }
        XCTAssertEqual((pending?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 23)

        defaults.set(false, forKey: NightSettings.reminderKey)
        RoutineNotificationManager.syncNightReminder(defaults: defaults)
        await RoutineNotificationManager.settle()
        pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .first { $0.identifier == RoutineNotificationManager.nightReminderIdentifier }
        XCTAssertNil(pending)
        defaults.removePersistentDomain(forName: suite)
    }

    /// Reminders show while the app is open; step alerts, which the app
    /// already chimes, do not.
    func testOnlyRemindersShowInTheForeground() {
        XCTAssertTrue(NotificationPresenter.shownInForeground.contains(RoutineNotificationManager.nightReminderIdentifier))
        XCTAssertTrue(NotificationPresenter.shownInForeground.contains(RoutineNotificationManager.reminderIdentifier))
        XCTAssertFalse(NotificationPresenter.shownInForeground.contains("rise-run-abc-step-0"))
    }

    /// The night reminder is one repeating calendar request at the goal,
    /// replaced when the goal moves and gone when it is switched off.
    func testNightReminderIsOneRepeatingRequestAtTheGoal() async {
        func pending() async -> UNNotificationRequest? {
            await UNUserNotificationCenter.current().pendingNotificationRequests()
                .first { $0.identifier == RoutineNotificationManager.nightReminderIdentifier }
        }

        RoutineNotificationManager.scheduleNightReminder(atMinutesAfterMidnight: 22 * 60 + 15)
        await RoutineNotificationManager.settle()
        let request = await pending()
        let trigger = request?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 22)
        XCTAssertEqual(trigger?.dateComponents.minute, 15)
        XCTAssertEqual(trigger?.repeats, true)

        RoutineNotificationManager.scheduleNightReminder(atMinutesAfterMidnight: 21 * 60)
        await RoutineNotificationManager.settle()
        let moved = await pending()
        XCTAssertEqual((moved?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 21)
        let all = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier == RoutineNotificationManager.nightReminderIdentifier }
        XCTAssertEqual(all.count, 1, "moving the goal replaces the request rather than adding one")

        RoutineNotificationManager.scheduleNightReminder(atMinutesAfterMidnight: nil)
        await RoutineNotificationManager.settle()
        let off = await pending()
        XCTAssertNil(off)
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
