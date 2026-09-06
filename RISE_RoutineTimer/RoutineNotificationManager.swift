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

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    static func schedule(_ alerts: [PlannedAlert], steps: [RunStep], now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for alert in alerts {
            let interval = alert.fireDate.timeIntervalSince(now)
            guard interval > 1, steps.indices.contains(alert.stepIndex) else { continue }

            let step = steps[alert.stepIndex]
            let content = UNMutableNotificationContent()
            content.sound = .default
            let identifier: String

            switch alert.kind {
            case .stepEnd:
                identifier = "rise-step-\(alert.stepIndex)"
                content.title = "\(step.title) is done"
                if steps.indices.contains(alert.stepIndex + 1) {
                    content.body = "Next: \(steps[alert.stepIndex + 1].title)"
                } else {
                    content.body = "That was the last step."
                }
            case .overtime(let minutes):
                identifier = "rise-over-\(alert.stepIndex)-\(minutes)"
                content.title = "\(step.title) is \(minutes) min over"
                content.body = "Tap the checkmark when you're done."
            case .completion:
                identifier = "rise-complete"
                content.title = "Routine complete"
                content.body = "Nice work. Your morning routine is finished."
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { error in
                if let error { print("Could not schedule \(identifier): \(error)") }
            }
        }
    }
}
