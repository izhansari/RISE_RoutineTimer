//
//  NotificationPresenter.swift
//  RISE_RoutineTimer
//
//  Decides what a notification does when it arrives while RISE is open.
//  Without a delegate iOS shows nothing at all in the foreground, so the
//  night reminder was silent whenever the app happened to be on screen at
//  the goal time.
//
//  The two reminders (the night's start goal, the morning's start-by) show
//  as a banner with sound. A running routine's step alerts do not: the app
//  already chimes and speaks each step in the foreground, and a banner on
//  top would say it twice.
//

import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let shownInForeground: Set<String> = [
        RoutineNotificationManager.nightReminderIdentifier,
        RoutineNotificationManager.reminderIdentifier,
    ]

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.shownInForeground.contains(notification.request.identifier) ? [.banner, .list, .sound] : []
    }
}
