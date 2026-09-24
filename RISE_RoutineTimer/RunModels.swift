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
    /// Which routine is being run. Declared last, with a default, so the
    /// memberwise initialiser's existing call sites keep compiling.
    var kind: RoutineKind = .morning

    var plannedSeconds: Int { steps.reduce(0) { $0 + $1.durationSeconds } }
}

nonisolated extension RoutineRun {
    /// In an extension so the memberwise initialiser survives. A run
    /// persisted by a build without `kind` is a morning run — the only kind
    /// there was — rather than a decode failure that drops it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decode([RunStep].self, forKey: .steps)
        phase = try container.decode(Phase.self, forKey: .phase)
        currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        stepAccumulated = try container.decode(TimeInterval.self, forKey: .stepAccumulated)
        stepResumedAt = try container.decodeIfPresent(Date.self, forKey: .stepResumedAt)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        totalPausedSeconds = try container.decode(TimeInterval.self, forKey: .totalPausedSeconds)
        results = try container.decode([StepResult].self, forKey: .results)
        overtimeAnnounced = try container.decode(Bool.self, forKey: .overtimeAnnounced)
        kind = try container.decodeIfPresent(RoutineKind.self, forKey: .kind) ?? .morning
    }
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
    /// Which routine this was a run of. Declared last, with a default, so
    /// the memberwise initialiser's existing call sites keep compiling.
    var kind: RoutineKind = .morning

    /// Positive means slower than planned, negative means faster.
    var deltaSeconds: Int { activeSeconds - plannedSeconds }
}

nonisolated extension SessionResult {
    /// In an extension so the memberwise initialiser survives. A result
    /// encoded before `kind` existed is a morning one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        plannedSeconds = try container.decode(Int.self, forKey: .plannedSeconds)
        activeSeconds = try container.decode(Int.self, forKey: .activeSeconds)
        pausedSeconds = try container.decode(Int.self, forKey: .pausedSeconds)
        completed = try container.decode(Bool.self, forKey: .completed)
        steps = try container.decode([StepResult].self, forKey: .steps)
        kind = try container.decodeIfPresent(RoutineKind.self, forKey: .kind) ?? .morning
    }
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
