//
//  TimeFormatting.swift
//  RISE_RoutineTimer
//
//  Small formatting helpers used by the editor and timer screens.
//

import Foundation

enum TimeFormatting {
    private static let shortClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter
    }()

    /// "4:05" style countdown text. Ignores sign; callers add "+" for overtime.
    static func clockTime(from seconds: Int) -> String {
        let absoluteSeconds = abs(seconds)
        let minutes = absoluteSeconds / 60
        let remainingSeconds = absoluteSeconds % 60

        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    static func shortClockTime(from date: Date) -> String {
        shortClockFormatter.string(from: date)
    }

    /// "5 min", "1 min 30 sec", "45 sec".
    static func durationText(from seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes == 0 {
            return "\(remainingSeconds) sec"
        }

        if remainingSeconds == 0 {
            return minutes == 1 ? "1 min" : "\(minutes) min"
        }

        return "\(minutes) min \(remainingSeconds) sec"
    }

    /// Natural wording for text-to-speech: "5 minutes", "1 minute 30 seconds".
    static func spokenDuration(from seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        var parts: [String] = []

        if minutes > 0 {
            parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        if remainingSeconds > 0 || parts.isEmpty {
            parts.append(remainingSeconds == 1 ? "1 second" : "\(remainingSeconds) seconds")
        }

        return parts.joined(separator: " ")
    }

    /// "1:30 AHEAD", "0:45 BEHIND", or "ON PLAN". Positive input means behind.
    static func scheduleDeltaText(from deltaSeconds: Int) -> String {
        if abs(deltaSeconds) < 1 { return "ON PLAN" }
        return "\(clockTime(from: deltaSeconds)) \(deltaSeconds < 0 ? "AHEAD" : "BEHIND")"
    }
}
