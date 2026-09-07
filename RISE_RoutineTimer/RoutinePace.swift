//
//  RoutinePace.swift
//  RISE_RoutineTimer
//
//  How far ahead or behind plan the current run is, as three plain states.
//  The active screen paints its whole fill with this, so the colour of the
//  screen *is* the ahead/behind signal — no corner full of small numbers.
//
//  Pure and nonisolated so the thresholds can be unit tested.
//

import SwiftUI

nonisolated enum RoutinePace: String, CaseIterable, Equatable {
    /// On plan, or ahead of it.
    case onTrack
    /// Slipping: behind, but still recoverable inside the current step.
    case slipping
    /// Meaningfully behind plan.
    case behind

    /// Slack allowed before "behind plan" is worth saying at all. A few
    /// seconds of drift is the normal cost of tapping a button.
    static let onTrackSlackSeconds = 30
    /// Past this many seconds behind, the screen goes red.
    static let behindThresholdSeconds = 180

    /// `deltaSeconds` is `RoutineEngine.scheduleDeltaSeconds`: positive means
    /// behind plan, negative means ahead. Overtime on the current step is
    /// already folded into it, so a step running long slides the pace on its
    /// own without a special case here.
    init(deltaSeconds: Int) {
        if deltaSeconds > Self.behindThresholdSeconds {
            self = .behind
        } else if deltaSeconds > Self.onTrackSlackSeconds {
            self = .slipping
        } else {
            self = .onTrack
        }
    }

    /// The rising fill colour. Deep and desaturated rather than system red /
    /// green: this is a full-screen wash at 6am, and white type has to stay
    /// legible on it. `behind` is the same ink MorningCheckin used for an
    /// over-budget tank, so the two apps agree on what "over" looks like.
    var fillColor: Color {
        switch self {
        case .onTrack:  return Color(hex: 0x14664B)
        case .slipping: return Color(hex: 0x8A5A00)
        case .behind:   return Color(hex: 0x7F2020)
        }
    }

    /// Tracked-caps label for the pace strip.
    func label(deltaSeconds: Int) -> String {
        switch self {
        case .onTrack:
            if deltaSeconds < -Self.onTrackSlackSeconds {
                return "\(TimeFormatting.clockTime(from: deltaSeconds)) AHEAD"
            }
            return "ON PLAN"
        case .slipping, .behind:
            return "\(TimeFormatting.clockTime(from: deltaSeconds)) BEHIND"
        }
    }
}

nonisolated extension Color {
    /// `Color(hex: 0x14664B)` — the palette above is written in hex so it can
    /// be compared against the web app's stylesheet at a glance.
    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255
        )
    }
}
