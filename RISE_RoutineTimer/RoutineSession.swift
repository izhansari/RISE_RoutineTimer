//
//  RoutineSession.swift
//  RISE_RoutineTimer
//
//  One finished (or abandoned) routine run, saved for history and stats.
//  Every property has a default so the model stays CloudKit-compatible.
//

import Foundation
import SwiftData

@Model
final class RoutineSession {
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var plannedSeconds: Int = 0
    var activeSeconds: Int = 0
    var pausedSeconds: Int = 0
    var completed: Bool = true
    var stepRecords: [StepResult] = []
    /// Which routine this was a run of (`RoutineKind.rawValue`). The default
    /// keeps every session saved before the night routine existed a morning.
    var kindRaw: String = RoutineKind.morning.rawValue

    var kind: RoutineKind { RoutineKind(rawValue: kindRaw) ?? .morning }
    /// For a night run, the start goal it was held to (minutes after
    /// midnight), recorded when the session was saved — see
    /// `MorningRecord.joinNights`. Nil for a morning, whose goal lives on
    /// its `MorningLog`, and for nights saved before goals were stored.
    var goalMinutes: Int?

    init(result: SessionResult, goalMinutes: Int? = nil) {
        startedAt = result.startedAt
        endedAt = result.endedAt
        plannedSeconds = result.plannedSeconds
        activeSeconds = result.activeSeconds
        pausedSeconds = result.pausedSeconds
        completed = result.completed
        stepRecords = result.steps
        kindRaw = result.kind.rawValue
        self.goalMinutes = goalMinutes
    }

    /// Writes a corrected copy of this run back (see `SessionResult.correcting`).
    /// The start time is the run's identity and never changes.
    func apply(_ corrected: SessionResult) {
        endedAt = corrected.endedAt
        plannedSeconds = corrected.plannedSeconds
        activeSeconds = corrected.activeSeconds
        pausedSeconds = corrected.pausedSeconds
        completed = corrected.completed
        stepRecords = corrected.steps
    }

    var result: SessionResult {
        SessionResult(
            startedAt: startedAt,
            endedAt: endedAt,
            plannedSeconds: plannedSeconds,
            activeSeconds: activeSeconds,
            pausedSeconds: pausedSeconds,
            completed: completed,
            steps: stepRecords,
            kind: kind
        )
    }
}

extension Array where Element == RoutineSession {
    /// The saved runs of one routine, as results. Everything that averages,
    /// ranks or streaks over sessions asks for one routine at a time — a
    /// night run is not a slow morning.
    func results(of kind: RoutineKind) -> [SessionResult] {
        filter { $0.kind == kind }.map(\.result)
    }
}

/// Saves finished runs. Abandoned runs are only kept when at least one step
/// was completed, so a mis-tapped Start doesn't clutter history.
final class SessionRecorder {
    private let context: ModelContext
    /// The night's start goal at the moment a night run is saved, stamped
    /// on the session so a later change of goal leaves it alone.
    private let nightGoal: () -> Int

    init(context: ModelContext, nightGoal: @escaping () -> Int = { NightSettings.storedTargetStart() }) {
        self.context = context
        self.nightGoal = nightGoal
    }

    func record(_ result: SessionResult) {
        guard result.completed || !result.steps.isEmpty else { return }
        let goal = result.kind == .night ? nightGoal() : nil
        context.insert(RoutineSession(result: result, goalMinutes: goal))
        do {
            try context.save()
        } catch {
            print("Could not save session: \(error)")
        }
    }
}
