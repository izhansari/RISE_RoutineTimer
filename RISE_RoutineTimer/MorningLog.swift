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
    /// The wake goal in force on this morning, minutes after midnight.
    ///
    /// Snooze used to be measured against whatever the goal was *now*, so
    /// moving the goal rewrote every morning behind it: nudge it half an
    /// hour later and the whole record gained half an hour of virtue. That
    /// is fatal for this app in particular, whose entire purpose is to walk
    /// the wake time earlier — without this, each move erased the evidence
    /// of the last one.
    ///
    /// Optional because rows written before it existed have none; they are
    /// backfilled once at launch (`ContentView.backfillWakeGoals`) and fall
    /// back to the current goal until then.
    var goalMinutes: Int?

    init(day: Date, wakeAt: Date? = nil, goalMinutes: Int? = nil) {
        self.day = day
        self.wakeAt = wakeAt
        self.goalMinutes = goalMinutes
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
            record.goalMinutes = log.goalMinutes
            byDay[day] = record
        }

        // Mornings only: a night run is not the morning routine started
        // late, and must not become the day's routine start. Nights are
        // joined by `joinNights` instead.
        for session in sessions where session.kind == .morning {
            let day = calendar.startOfDay(for: session.startedAt)
            var record = byDay[day] ?? MorningRecord(day: day)
            if let existing = record.routineStartAt, existing <= session.startedAt {
                continue
            }
            record.routineStartAt = session.startedAt
            record.routineEndAt = session.endedAt
            record.routineActiveSeconds = session.activeSeconds
            record.completedRoutine = session.completed
            byDay[day] = record
        }

        return byDay.values.sorted { $0.day > $1.day }
    }
}

// MARK: - Nights

extension MorningRecord {
    /// The evening a night run belongs to. A night routine that begins at
    /// half past midnight is still the night before, so the day turns over
    /// at noon rather than at midnight.
    nonisolated static func nightDay(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-12 * 60 * 60))
    }

    /// One record per night out of the night routine's sessions, in the
    /// same shape the morning uses so the charts, baselines and insights
    /// are shared. There is no wake to log at night — you are already up —
    /// so the record's "wake" is the moment the routine began: its snooze
    /// is how late that was against the night's start goal, its activation
    /// is nought, and its box is the routine. The goal is the one stored on
    /// the session when it was saved (`RoutineSession.goalMinutes`), for the
    /// same reason the morning stores it: moving the goal must not rewrite
    /// the nights already had.
    static func joinNights(
        sessions: [RoutineSession],
        calendar: Calendar = .current
    ) -> [MorningRecord] {
        var byNight: [Date: MorningRecord] = [:]

        for session in sessions where session.kind == .night {
            let night = nightDay(of: session.startedAt, calendar: calendar)
            // The first run of the evening is the night; a second one is a
            // retake and does not move it.
            if let existing = byNight[night]?.routineStartAt, existing <= session.startedAt {
                continue
            }
            var record = MorningRecord(day: night)
            record.wakeAt = session.startedAt
            record.routineStartAt = session.startedAt
            record.routineEndAt = session.endedAt
            record.routineActiveSeconds = session.activeSeconds
            record.completedRoutine = session.completed
            record.goalMinutes = session.goalMinutes
            byNight[night] = record
        }

        return byNight.values.sorted { $0.day > $1.day }
    }
}

/// Reads and writes today's wake time. Mirrors `SessionRecorder`.
// MARK: - Store

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
    /// Records the moment of waking, and the goal it is measured against.
    /// Writing it twice on one day overwrites, so a mis-tap can be corrected
    /// by tapping again.
    func recordWake(at date: Date, existing logs: [MorningLog], goalMinutes: Int) {
        let day = calendar.startOfDay(for: date)
        if let today = log(logs, dayOf: date) {
            today.wakeAt = date
            today.goalMinutes = goalMinutes
        } else {
            context.insert(MorningLog(day: day, wakeAt: date, goalMinutes: goalMinutes))
        }
        save()
    }

    /// Called as a routine starts. Logs the start as the wake time when the
    /// morning has none — see `MorningSettings.impliedWake`. Returns whether
    /// it wrote anything.
    @discardableResult
    func recordWakeImplied(byRoutineStartingAt start: Date, kind: RoutineKind = .morning, settings: MorningSettings) -> Bool {
        let logs = (try? context.fetch(FetchDescriptor<MorningLog>())) ?? []
        let existing = log(logs, dayOf: start)?.wakeAt
        guard let wake = settings.impliedWake(routineStart: start, kind: kind, existingWake: existing, calendar: calendar) else {
            return false
        }
        recordWake(at: wake, existing: logs, goalMinutes: settings.targetWakeMinutes)
        return true
    }

    func setWake(_ wakeAt: Date?, on date: Date, existing logs: [MorningLog], goalMinutes: Int) {
        let day = calendar.startOfDay(for: date)
        if let today = log(logs, dayOf: date) {
            today.wakeAt = wakeAt
            // Clearing the wake leaves the goal alone: the morning still
            // happened under it, and logging a wake again is the same day.
            if wakeAt != nil { today.goalMinutes = goalMinutes }
        } else if let wakeAt {
            context.insert(MorningLog(day: day, wakeAt: wakeAt, goalMinutes: goalMinutes))
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
