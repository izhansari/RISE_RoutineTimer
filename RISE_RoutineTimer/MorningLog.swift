//
//  MorningLog.swift
//  RISE_RoutineTimer
//
//  The one thing the routine timer cannot work out for itself: what time you
//  actually woke up. Everything else a morning is scored on already falls out
//  of `RoutineSession`.
//
//  Kept as its own model rather than a field on `RoutineSession` because the
//  wake moment is logged *before* any routine exists — and on a day you never
//  run the routine, the wake time is still worth having.
//
//  Every property defaults, so the model stays CloudKit-compatible like
//  `RoutineSession`.
//

import Foundation
import SwiftData

@Model
final class MorningLog {
    /// Start of the local day this belongs to — the row's identity.
    var day: Date = Date()
    var wakeAt: Date?

    init(day: Date, wakeAt: Date? = nil) {
        self.day = day
        self.wakeAt = wakeAt
    }
}

// MARK: - Joining logs and sessions into records

extension MorningRecord {
    /// Builds one record per day out of the wake log and the recorded runs.
    ///
    /// A day with several runs keeps the earliest, which is the morning one;
    /// a later evening run shouldn't overwrite how the morning went.
    @MainActor
    static func join(
        logs: [MorningLog],
        sessions: [RoutineSession],
        calendar: Calendar = .current
    ) -> [MorningRecord] {
        var byDay: [Date: MorningRecord] = [:]

        for log in logs {
            let day = calendar.startOfDay(for: log.day)
            var record = byDay[day] ?? MorningRecord(day: day)
            record.wakeAt = log.wakeAt
            byDay[day] = record
        }

        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            var record = byDay[day] ?? MorningRecord(day: day)
            if let existing = record.routineStartAt, existing <= session.startedAt {
                continue
            }
            record.routineStartAt = session.startedAt
            record.routineEndAt = session.endedAt
            record.completedRoutine = session.completed
            byDay[day] = record
        }

        return byDay.values.sorted { $0.day > $1.day }
    }
}

// MARK: - Store

/// Reads and writes today's wake time. Mirrors `SessionRecorder`.
@MainActor
final class MorningLogStore {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func log(_ logs: [MorningLog], dayOf date: Date) -> MorningLog? {
        let day = calendar.startOfDay(for: date)
        return logs.first { calendar.startOfDay(for: $0.day) == day }
    }

    /// Records the moment of waking. Writing it twice on one day overwrites,
    /// so a mis-tap can be corrected by tapping again.
    func recordWake(at date: Date, existing logs: [MorningLog]) {
        let day = calendar.startOfDay(for: date)
        if let today = log(logs, dayOf: date) {
            today.wakeAt = date
        } else {
            context.insert(MorningLog(day: day, wakeAt: date))
        }
        save()
    }

    func setWake(_ wakeAt: Date?, on date: Date, existing logs: [MorningLog]) {
        let day = calendar.startOfDay(for: date)
        if let today = log(logs, dayOf: date) {
            today.wakeAt = wakeAt
        } else if let wakeAt {
            context.insert(MorningLog(day: day, wakeAt: wakeAt))
        }
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Could not save morning log: \(error)")
        }
    }
}
