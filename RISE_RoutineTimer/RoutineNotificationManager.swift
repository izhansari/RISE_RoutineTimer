//
//  RoutineNotificationManager.swift
//  RISE_RoutineTimer
//
//  A small wrapper around local notifications for routine step alerts.
//

import Foundation
import UserNotifications

@MainActor
enum RoutineNotificationManager {
    private static let notificationPrefix = "routine-step-"
    private static let completionIdentifier = "routine-complete"

    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .notDetermined else {
            return
        }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // The app can still run without notifications, so we avoid showing
            // an error UI for this first version.
            print("Notification permission request failed: \(error)")
        }
    }

    static func cancelRoutineNotifications() {
        let identifiers = (0..<100).map { "\(notificationPrefix)\($0)" } + [completionIdentifier]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    static func scheduleNotifications(
        steps: [RoutineStep],
        currentIndex: Int,
        stepStartDate: Date,
        now: Date = Date()
    ) {
        cancelRoutineNotifications()

        guard steps.indices.contains(currentIndex) else {
            return
        }

        var scheduledEndDate = stepStartDate.addingTimeInterval(TimeInterval(steps[currentIndex].durationSeconds))

        for index in currentIndex..<steps.count {
            let step = steps[index]
            let interval = scheduledEndDate.timeIntervalSince(now)

            if interval > 1 {
                addStepNotification(
                    identifier: "\(notificationPrefix)\(index)",
                    title: "\(step.title) is done",
                    body: nextStepBody(after: index, in: steps),
                    interval: interval
                )

                if index == steps.count - 1 {
                    addStepNotification(
                        identifier: completionIdentifier,
                        title: "Routine complete",
                        body: "Nice work. Your morning routine is finished.",
                        interval: interval
                    )
                }
            }

            // Future timing is only predictable while each previous step auto-advances.
            // A manual step can run overtime, so we reschedule after the user taps Next.
            guard step.autoNext else {
                break
            }

            if steps.indices.contains(index + 1) {
                scheduledEndDate = scheduledEndDate.addingTimeInterval(TimeInterval(steps[index + 1].durationSeconds))
            }
        }
    }

    private static func nextStepBody(after index: Int, in steps: [RoutineStep]) -> String {
        guard steps.indices.contains(index + 1) else {
            return "That was the final step."
        }

        return "Next: \(steps[index + 1].title)"
    }

    private static func addStepNotification(
        identifier: String,
        title: String,
        body: String,
        interval: TimeInterval
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Could not schedule notification \(identifier): \(error)")
            }
        }
    }
}
