//
//  RoutinePace.swift
//  RISE_RoutineTimer
//
//  What colour the active screen's fill is, and why.
//
//  The fill used to be painted from `scheduleDeltaSeconds`, the *cumulative*
//  ahead/behind figure for the whole run. That made one slow step stain every
//  step after it — once you were behind, the screen stayed amber to the end
//  and stopped telling you anything about what you were currently doing.
//
//  So the fill is now a **per-step** signal and resets with each step:
//
//      within the planned duration → the colour the user picked
//      running over                → amber
//      running well over           → red
//
//  Only manual (auto-next off) steps can ever reach those last two, because
//  `RoutineEngine.tick()` advances an auto-next step the moment its time is
//  up. That is the point: overtime *means* "this step is waiting on you".
//
//  The cumulative ahead/behind figure is still shown, as text, in the PACE
//  micro-stat — a number that can be read when wanted rather than a wash that
//  cannot be escaped.
//

import SwiftUI

// MARK: - The user's colour

/// The fill colour while a step is running to plan.
///
/// Saturated, in the FLIP timer's register — that app fills the screen with a
/// flat, confident red or green and puts white type straight on it. The first
/// pass here used deep desaturated inks and read as muted, which is not the
/// look. These are dark enough for white type and no darker.
///
/// Deliberately excludes every amber and red: those are reserved for overtime,
/// and a user who picked "rust" as their normal colour would have no way to
/// tell the two states apart.
nonisolated enum FillTheme: String, CaseIterable, Identifiable, Equatable {
    case green, ocean, indigo, violet, ink

    static let storageKey = "activeFillTheme"
    static let `default` = FillTheme.green

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green:  return "Green"
        case .ocean:  return "Ocean"
        case .indigo: return "Indigo"
        case .violet: return "Violet"
        case .ink:    return "Ink"
        }
    }

    var color: Color {
        switch self {
        case .green:  return Color(hex: 0x0FA057)
        case .ocean:  return Color(hex: 0x0C6ED6)
        case .indigo: return Color(hex: 0x4A32DC)
        case .violet: return Color(hex: 0x9A22C8)
        case .ink:    return Color(hex: 0x171717)
        }
    }
}

// MARK: - Per-step state

nonisolated enum StepPace: String, CaseIterable, Equatable {
    /// Still inside the step's planned duration.
    case onTime
    /// Past the planned duration, but only just.
    case running
    /// Past the planned duration by enough to want attention.
    case over

    /// Seconds of overtime before amber becomes red.
    static let overThresholdSeconds = 120

    init(overtimeSeconds: Int) {
        if overtimeSeconds <= 0 {
            self = .onTime
        } else if overtimeSeconds < Self.overThresholdSeconds {
            self = .running
        } else {
            self = .over
        }
    }

    /// Colour is never the only cue — the countdown flips to "+M:SS" and the
    /// status pill changes wording too, so the state survives being colour-blind
    /// or glancing at the screen from across the room.
    func fillColor(theme: FillTheme) -> Color {
        switch self {
        case .onTime:  return theme.color
        case .running: return Color(hex: 0xE8890A)
        case .over:    return Color(hex: 0xDB2118)
        }
    }

    var isOvertime: Bool { self != .onTime }
}

// MARK: - Cumulative pace, as text only

nonisolated enum RoutinePace {
    /// Slack allowed before "behind plan" is worth saying at all.
    static let onTrackSlackSeconds = 30

    /// How far behind the *routine* has to be before the active screen breaks
    /// its silence. Step-level overtime is already carried by the fill colour
    /// and the "+" countdown, so this is only about the run as a whole.
    static let behindAlertSeconds = 120

    /// "ON PLAN", "1:30 AHEAD" or "2:05 BEHIND" for the PACE micro-stat.
    /// `deltaSeconds` is `RoutineEngine.scheduleDeltaSeconds`: positive is behind.
    static func label(deltaSeconds: Int) -> String {
        if abs(deltaSeconds) <= onTrackSlackSeconds { return "ON PLAN" }
        let text = TimeFormatting.clockTime(from: deltaSeconds)
        return deltaSeconds < 0 ? "\(text) AHEAD" : "\(text) BEHIND"
    }
}

nonisolated extension Color {
    /// `Color(hex: 0x14664B)` — the palette is written in hex so it can be
    /// compared against the web app's stylesheet at a glance.
    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255
        )
    }
}
