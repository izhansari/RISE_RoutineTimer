//
//  DebugSeed.swift
//  RISE_RoutineTimer
//
//  Development-only sample history, ported from MorningCheckin's
//  `seedData.js`: 13 days that gradually improve, with two missed days, so
//  the charts, baselines, budgets and streak logic can all be seen with
//  plausible numbers instead of waiting two weeks.
//
//  Compiled out of release builds entirely.
//

#if DEBUG

import Foundation
import SwiftData

@MainActor
enum DebugSeed {
    /// Wipes any existing sample data and writes a fresh 13-day run-up.
    static func populate(context: ModelContext, steps: [RoutineStep], settings: MorningSettings) {
        clear(context: context)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let missedDayIndices: Set<Int> = [3, 8]

        for daysAgo in stride(from: 13, through: 1, by: -1) {
            let dayIndex = 13 - daysAgo
            if missedDayIndices.contains(dayIndex) { continue }
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }

            // 0 (oldest) → 1 (yesterday): mornings get tighter over time.
            let progress = Double(dayIndex) / 12
            let jitter = { (spread: Double) in Double.random(in: -spread / 2...spread / 2) }

            let snoozeMinutes = max(-5, (35 - progress * 30 + jitter(10)).rounded())
            let activationMinutes = max(5, (24 - progress * 14 + jitter(6)).rounded())
            let durationMinutes = max(12, (30 - progress * 8 + jitter(6)).rounded())

            let wakeAt = day
                .addingTimeInterval(TimeInterval(settings.targetWakeMinutes * 60))
                .addingTimeInterval(snoozeMinutes * 60)
            let routineStart = wakeAt.addingTimeInterval(activationMinutes * 60)
            let routineEnd = routineStart.addingTimeInterval(durationMinutes * 60)

            context.insert(MorningLog(day: day, wakeAt: wakeAt))
            context.insert(RoutineSession(result: SessionResult(
                startedAt: routineStart,
                endedAt: routineEnd,
                plannedSeconds: steps.reduce(0) { $0 + $1.durationSeconds },
                activeSeconds: Int(durationMinutes * 60),
                pausedSeconds: 0,
                completed: true,
                steps: stepResults(for: steps, totalSeconds: Int(durationMinutes * 60))
            )))
        }

        save(context)
    }

    static func clear(context: ModelContext) {
        try? context.delete(model: MorningLog.self)
        try? context.delete(model: RoutineSession.self)
        save(context)
    }

    /// Splits the seeded routine length across the real steps in proportion to
    /// their planned durations, so the per-step suggestions have something to
    /// chew on too.
    private static func stepResults(for steps: [RoutineStep], totalSeconds: Int) -> [StepResult] {
        let planned = steps.reduce(0) { $0 + $1.durationSeconds }
        guard planned > 0 else { return [] }
        return steps.map { step in
            let share = Double(step.durationSeconds) / Double(planned)
            let actual = Int((Double(totalSeconds) * share).rounded())
            return StepResult(
                stepID: step.stepID,
                title: step.title,
                plannedSeconds: step.durationSeconds,
                actualSeconds: max(1, actual),
                autoAdvanced: step.autoNext
            )
        }
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Could not seed sample data: \(error)")
        }
    }
}

#endif
