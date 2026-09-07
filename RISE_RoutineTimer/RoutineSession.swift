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

    init(result: SessionResult) {
        startedAt = result.startedAt
        endedAt = result.endedAt
        plannedSeconds = result.plannedSeconds
        activeSeconds = result.activeSeconds
        pausedSeconds = result.pausedSeconds
        completed = result.completed
        stepRecords = result.steps
    }

    var result: SessionResult {
        SessionResult(
            startedAt: startedAt,
            endedAt: endedAt,
            plannedSeconds: plannedSeconds,
            activeSeconds: activeSeconds,
            pausedSeconds: pausedSeconds,
            completed: completed,
            steps: stepRecords
        )
    }
}

/// Saves finished runs. Abandoned runs are only kept when at least one step
/// was completed, so a mis-tapped Start doesn't clutter history.
final class SessionRecorder {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(_ result: SessionResult) {
        guard result.completed || !result.steps.isEmpty else { return }
        context.insert(RoutineSession(result: result))
        do {
            try context.save()
        } catch {
            print("Could not save session: \(error)")
        }
    }
}
