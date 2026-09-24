//
//  RoutineKind.swift
//  RISE_RoutineTimer
//
//  Which routine a step, a run or a saved session belongs to. The app grew
//  up around one morning routine; the night routine is the second. A kind is
//  stamped on every step (so the two lists are kept apart), on the run (so
//  the timer knows what it is running) and on every saved session (so the
//  night's runs never leak into the morning's averages, streak or the
//  accountability charts, which are about mornings only).
//

import Foundation

nonisolated enum RoutineKind: String, Codable, CaseIterable, Identifiable, Equatable {
    case morning
    case night

    var id: String { rawValue }

    /// The Run tab's title.
    var title: String {
        switch self {
        case .morning: return "Morning Routine"
        case .night: return "Night Routine"
        }
    }

    /// The tracked-caps switch label.
    var label: String {
        switch self {
        case .morning: return "MORNING"
        case .night: return "NIGHT"
        }
    }

    /// "your morning routine", "your night routine".
    var noun: String { rawValue }

    var symbol: String {
        switch self {
        case .morning: return "sun.max"
        case .night: return "moon"
        }
    }

    /// Which routine the Run tab is showing, kept across launches.
    static let selectionKey = "selectedRoutineKind"
}
