//
//  TargetSchedule.swift
//  RISE_RoutineTimer
//
//  "Out the door by 7:30" math. The target is stored as minutes after
//  midnight; everything else is derived from the planned routine length.
//

import Foundation

nonisolated struct TargetSchedule: Equatable {
    static let targetKey = "routineTargetEndMinutes"
    static let reminderKey = "routineReminderEnabled"
    static let none = -1

    var targetMinutesAfterMidnight: Int
    var calendar: Calendar

    init(targetMinutesAfterMidnight: Int, calendar: Calendar = .current) {
        self.targetMinutesAfterMidnight = targetMinutesAfterMidnight
        self.calendar = calendar
    }

    var isSet: Bool { targetMinutesAfterMidnight >= 0 }

    /// The target as a clock time on the same day as `date`.
    func targetDate(on date: Date) -> Date? {
        guard isSet else { return nil }
        return calendar.startOfDay(for: date).addingTimeInterval(TimeInterval(targetMinutesAfterMidnight * 60))
    }

    /// Latest moment to press Start and still finish on time.
    func startByDate(on date: Date, plannedSeconds: Int) -> Date? {
        targetDate(on: date)?.addingTimeInterval(TimeInterval(-plannedSeconds))
    }

    /// A run this far from the target (an evening run against a morning
    /// target, say) isn't really aiming for it, so no spare-time label.
    static let relevanceWindow: TimeInterval = 3 * 60 * 60

    /// Positive when the projected end is before the target (time to spare),
    /// negative when it is past the target. Nil when the target is unset or
    /// the run is outside `relevanceWindow`.
    func spareSeconds(projectedEnd: Date) -> Int? {
        guard let target = targetDate(on: projectedEnd) else { return nil }
        let spare = target.timeIntervalSince(projectedEnd)
        guard abs(spare) <= Self.relevanceWindow else { return nil }
        return Int(spare.rounded())
    }

    /// Hour and minute of the start-by time, for a daily reminder.
    func startByComponents(plannedSeconds: Int) -> DateComponents? {
        guard isSet else { return nil }
        var minutes = targetMinutesAfterMidnight - plannedSeconds / 60
        while minutes < 0 { minutes += 24 * 60 }
        return DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    static func spareText(_ spare: Int) -> String {
        if abs(spare) < 30 { return "ON TARGET" }
        let text = TimeFormatting.clockTime(from: spare)
        return spare > 0 ? "\(text) TO SPARE" : "\(text) PAST TARGET"
    }
}
