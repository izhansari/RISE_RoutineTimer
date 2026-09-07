//
//  RunModels.swift
//  RISE_RoutineTimer
//
//  Plain value types that describe a routine run. They are frozen copies of
//  the SwiftData steps so an in-progress run is immune to edits, and they are
//  Codable so a run survives the app being killed.
//

import Foundation

nonisolated struct RunStep: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var icon: String
    var durationSeconds: Int
    var autoNext: Bool
    var notes: String
    var autoShowNotes: Bool

    init(
        id: UUID = UUID(),
        title: String,
        icon: String = "",
        durationSeconds: Int,
        autoNext: Bool = true,
        notes: String = "",
        autoShowNotes: Bool = true
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.durationSeconds = max(1, durationSeconds)
        self.autoNext = autoNext
        self.notes = notes
        self.autoShowNotes = autoShowNotes
    }

    /// Written by hand rather than synthesised so a run persisted by an older
    /// build still decodes — the synthesised initialiser throws on a missing
    /// key even when the property has a default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        autoNext = try container.decode(Bool.self, forKey: .autoNext)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        autoShowNotes = try container.decodeIfPresent(Bool.self, forKey: .autoShowNotes) ?? true
    }

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension RunStep {
    @MainActor
    init(_ model: RoutineStep) {
        self.init(
            id: model.stepID,
            title: model.title,
            icon: model.icon,
            durationSeconds: model.durationSeconds,
            autoNext: model.autoNext,
            notes: model.notes,
            autoShowNotes: model.autoShowNotes
        )
    }
}

/// What actually happened on one finished step.
nonisolated struct StepResult: Codable, Equatable {
    var stepID: UUID
    var title: String
    var plannedSeconds: Int
    var actualSeconds: Int
    var autoAdvanced: Bool
    /// Set when the user skipped rather than finished. Optional so sessions
    /// written before skipping existed still decode (a missing key on an
    /// optional decodes as nil; on a non-optional it would throw).
    var skipped: Bool?

    var wasSkipped: Bool { skipped == true }

    var deltaSeconds: Int { actualSeconds - plannedSeconds }
}

/// The full state of one run. Only `RoutineEngine` mutates this.
nonisolated struct RoutineRun: Codable, Equatable {
    enum Phase: String, Codable {
        case running
        case paused
        case complete
    }

    var steps: [RunStep]
    var phase: Phase
    var currentIndex: Int
    var startedAt: Date
    var endedAt: Date?

    /// Seconds already spent on the current step before the latest resume.
    var stepAccumulated: TimeInterval
    /// Wall-clock moment the current step last (re)started counting. Nil while paused or complete.
    var stepResumedAt: Date?
    var pausedAt: Date?
    var totalPausedSeconds: TimeInterval
    var results: [StepResult]
    /// True once the overtime alert has fired for the current step.
    var overtimeAnnounced: Bool

    var plannedSeconds: Int { steps.reduce(0) { $0 + $1.durationSeconds } }
}

/// Summary handed out when a run finishes or is abandoned. Session history
/// (a later phase) persists these.
nonisolated struct SessionResult: Codable, Equatable, Identifiable {
    var id: Date { startedAt }
    var startedAt: Date
    var endedAt: Date
    var plannedSeconds: Int
    var activeSeconds: Int
    var pausedSeconds: Int
    var completed: Bool
    var steps: [StepResult]

    /// Positive means slower than planned, negative means faster.
    var deltaSeconds: Int { activeSeconds - plannedSeconds }
}

/// One local notification the engine wants scheduled.
nonisolated struct PlannedAlert: Equatable {
    enum Kind: Equatable {
        case stepEnd
        case overtime(minutes: Int)
        case completion
    }

    var stepIndex: Int
    var fireDate: Date
    var kind: Kind
}
