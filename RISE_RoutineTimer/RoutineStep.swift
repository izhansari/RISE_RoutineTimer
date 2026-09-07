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

    // Optional single emoji shown next to the title.
    var icon: String = ""

    // Store time as total seconds so the timer math stays simple.
    var durationSeconds: Int

    // When true, the runner moves to the next step as soon as time is up.
    // When false, the runner stays on this step and counts overtime.
    var autoNext: Bool

    // Optional helper text shown during the routine.
    var notes: String

    // When true (and there are notes), the notes sheet opens by itself as the
    // step starts, so a reminder you wrote for yourself is not something you
    // have to remember to go and look at.
    var autoShowNotes: Bool = true

    // SwiftData does not preserve List order automatically, so we save it.
    var sortOrder: Int

    init(
        stepID: UUID = UUID(),
        title: String,
        icon: String = "",
        durationSeconds: Int,
        autoNext: Bool = true,
        notes: String = "",
        autoShowNotes: Bool = true,
        sortOrder: Int
    ) {
        self.stepID = stepID
        self.title = title
        self.icon = icon
        self.durationSeconds = max(1, durationSeconds)
        self.autoNext = autoNext
        self.notes = notes
        self.autoShowNotes = autoShowNotes
        self.sortOrder = sortOrder
    }
}

extension RoutineStep {
    /// Bumping this replaces the saved routine with `starterRoutine` on the
    /// next launch — see `ContentView.seedStarterRoutineIfNeeded()`. It wipes
    /// any edits made on the device, so only bump it when the owner has
    /// actually asked for the routine to be reloaded.
    static let starterRoutineVersion = 2

    /// The owner's real morning routine.
    static let starterRoutine: [RoutineStepSeed] = [
        RoutineStepSeed(title: "Dua", icon: "🙏", durationSeconds: 300, autoNext: false, notes: ""),
        RoutineStepSeed(title: "Drink Water", icon: "💧", durationSeconds: 60, autoNext: true, notes: ""),
        RoutineStepSeed(title: "Make Bed", icon: "🛏️", durationSeconds: 60, autoNext: false, notes: ""),
        RoutineStepSeed(title: "Fold night clothes / necklace / toothpaste", icon: "🧺", durationSeconds: 75, autoNext: true, notes: ""),
        RoutineStepSeed(title: "Brush / toilet", icon: "🪥", durationSeconds: 225, autoNext: false, notes: ""),
        RoutineStepSeed(title: "Start shower / jump in", icon: "🚿", durationSeconds: 105, autoNext: true, notes: ""),
        RoutineStepSeed(title: "Shampoo", icon: "🧴", durationSeconds: 75, autoNext: true, notes: ""),
        RoutineStepSeed(title: "Face wash", icon: "🧼", durationSeconds: 75, autoNext: true, notes: ""),
        RoutineStepSeed(title: "End body wash", icon: "🛁", durationSeconds: 75, autoNext: true, notes: ""),
        RoutineStepSeed(title: "Towel / mouthwash", icon: "🦷", durationSeconds: 80, autoNext: false, notes: ""),
        RoutineStepSeed(title: "Boxers / deo / towel / skincare", icon: "🪒", durationSeconds: 195, autoNext: true, notes: ""),
        RoutineStepSeed(title: "Attar / watch / chain", icon: "⌚", durationSeconds: 50, autoNext: false, notes: ""),
        RoutineStepSeed(title: "Getting dressed / socks", icon: "👔", durationSeconds: 195, autoNext: true, notes: ""),
        RoutineStepSeed(title: "Tasbeeh, niyyat & shukr", icon: "📿", durationSeconds: 300, autoNext: false, notes: ""),
        RoutineStepSeed(title: "Coffee", icon: "☕", durationSeconds: 720, autoNext: false, notes: ""),
        RoutineStepSeed(title: "Tongue scraper", icon: "👅", durationSeconds: 60, autoNext: false, notes: "")
    ]
}

// A lightweight seed type keeps the default routine separate from SwiftData.
struct RoutineStepSeed {
    let title: String
    let icon: String
    let durationSeconds: Int
    let autoNext: Bool
    let notes: String
}

extension RoutineStep {
    /// Anything shorter than this is not a usable timer step.
    static let minimumDurationSeconds = 5

    static let untitled = "Untitled Step"

    /// Keeps only the first grapheme cluster, so the icon is one emoji.
    static func normalizedIcon(_ text: String) -> String {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "" }
        return String(first)
    }
}
