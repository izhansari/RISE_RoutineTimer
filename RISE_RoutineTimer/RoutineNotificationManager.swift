//
//  RoutineNotificationManager.swift
//  RISE_RoutineTimer
//
//  Local notifications for when the app is in the background. The engine
//  decides *what* to schedule (see `RoutineEngine.plannedAlerts`); this file
//  only turns that plan into requests.
//

import Foundation
import UserNotifications

enum RoutineNotificationManager {
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("Notification permission request failed: \(error)")
        }
    }

    private static let runPrefix = "rise-run-"
    private static let reminderIdentifier = "rise-daily-reminder"

    /// Every change to the run's alerts goes through this one queue, in the
    /// order it was asked for.
    ///
    /// Clearing the old alerts means asking the notification centre what is
    /// pending, which answers *later* — and the first version removed whatever
    /// that answer named after the new alerts had already been added. A chain
    /// of auto steps is scheduled whole, so the next step's plan reuses the
    /// identifiers the last one had ("step 3 ends" is in both), and each
    /// reschedule deleted every alert it had just made: a phone locked for the
    /// shower steps got no step-end notifications at all.
    /// `RoutineNotificationTests` pins it against the real centre.
    private static var queue: Task<Void, Never>?

    private static func enqueue(_ work: @escaping () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }

    /// Returns once everything asked for so far has reached the centre.
    static func settle() async {
        await queue?.value
    }

    /// Removes the alerts for the current run but leaves the daily reminder alone.
    static func cancelRunAlerts() {
        enqueue { await removePendingRunAlerts() }
    }

    private static func removePendingRunAlerts() async {
        let center = UNUserNotificationCenter.current()
        let ids: [String] = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier).filter { $0.hasPrefix(runPrefix) })
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// A repeating "time to start" nudge at the start-by time, or nothing.
    static func scheduleDailyReminder(at components: DateComponents?, targetText: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        guard let components else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to start your routine"
        content.body = "Start now to be done by \(targetText)."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)) { error in
            if let error { print("Could not schedule reminder: \(error)") }
        }
    }

    static func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    static func schedule(_ alerts: [PlannedAlert], steps: [RunStep], now: Date = Date()) {
        enqueue {
            await removePendingRunAlerts()

            // Unique to this pass, so a removal can only ever name alerts
            // from an earlier one — belt and braces with the queue.
            let pass = "\(runPrefix)\(UUID().uuidString.prefix(8))-"
            let center = UNUserNotificationCenter.current()

            for alert in alerts {
                let interval = alert.fireDate.timeIntervalSince(now)
                guard interval > 1, steps.indices.contains(alert.stepIndex) else { continue }

                let step = steps[alert.stepIndex]
                let content = UNMutableNotificationContent()
                content.sound = .default
                let identifier: String

                switch alert.kind {
                case .stepEnd:
                    identifier = "\(pass)step-\(alert.stepIndex)"
                    content.title = "\(step.title) is done"
                    if steps.indices.contains(alert.stepIndex + 1) {
                        content.body = "Next: \(steps[alert.stepIndex + 1].title)"
                    } else {
                        content.body = "That was the last step."
                    }
                case .overtime(let minutes):
                    identifier = "\(pass)over-\(alert.stepIndex)-\(minutes)"
                    content.title = "\(step.title) is \(minutes) min over"
                    content.body = "Tap the checkmark when you're done."
                case .completion:
                    identifier = "\(pass)complete"
                    content.title = "Routine complete"
                    content.body = "Nice work. Your morning routine is finished."
                }

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                do {
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                } catch {
                    print("Could not schedule \(identifier): \(error)")
                }
            }
        }
    }
}
