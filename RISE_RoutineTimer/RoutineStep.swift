//
//  RoutineStep.swift
//  RISE_RoutineTimer
//
//  This file defines the one piece of data the app saves: a routine step.
//

import Foundation
import SwiftData

@Model
final class RoutineStep {
    // Stable identity that survives renames, so history can match a step over time.
    var stepID: UUID = UUID()

    // The task name users see in the editor and timer.
    var title: String

    // Store time as total seconds so the timer math stays simple.
    var durationSeconds: Int

    // When true, the runner moves to the next step as soon as time is up.
    // When false, the runner stays on this step and counts overtime.
    var autoNext: Bool

    // Optional helper text shown during the routine.
    var notes: String

    // SwiftData does not preserve List order automatically, so we save it.
    var sortOrder: Int

    init(
        stepID: UUID = UUID(),
        title: String,
        durationSeconds: Int,
        autoNext: Bool = true,
        notes: String = "",
        sortOrder: Int
    ) {
        self.stepID = stepID
        self.title = title
        self.durationSeconds = max(1, durationSeconds)
        self.autoNext = autoNext
        self.notes = notes
        self.sortOrder = sortOrder
    }
}

extension RoutineStep {
    // These defaults make a new install useful immediately. Edit them here if
    // you want the app to start with a different morning routine.
    static let starterRoutine: [RoutineStepSeed] = [
        RoutineStepSeed(
            title: "Drink Water",
            durationSeconds: 2 * 60,
            autoNext: true,
            notes: "Start gently. A glass of water helps make the first win easy."
        ),
        RoutineStepSeed(
            title: "Stretch",
            durationSeconds: 5 * 60,
            autoNext: true,
            notes: "Loosen your neck, shoulders, hips, and back."
        ),
        RoutineStepSeed(
            title: "Wash Up",
            durationSeconds: 10 * 60,
            autoNext: false,
            notes: "Auto-next is off here so you can finish without rushing."
        ),
        RoutineStepSeed(
            title: "Plan The Day",
            durationSeconds: 5 * 60,
            autoNext: true,
            notes: "Pick the top one or two things that will make today successful."
        )
    ]
}

// A lightweight seed type keeps the default routine separate from SwiftData.
struct RoutineStepSeed {
    let title: String
    let durationSeconds: Int
    let autoNext: Bool
    let notes: String
}

extension RoutineStep {
    /// Anything shorter than this is not a usable timer step.
    static let minimumDurationSeconds = 5
}
