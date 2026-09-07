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

    private static let hourMinuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    /// "5:12 – 5:57 AM": one meridiem when both ends share it, both when a
    /// range crosses noon or midnight.
    static func clockRange(from start: Date, to end: Date) -> String {
        let calendar = Calendar.current
        let startAM = calendar.component(.hour, from: start) < 12
        let endAM = calendar.component(.hour, from: end) < 12
        let s = hourMinuteFormatter.string(from: start)
        let e = hourMinuteFormatter.string(from: end)
        if startAM == endAM {
            return "\(s) – \(e) \(endAM ? "AM" : "PM")"
        }
        return "\(s) \(startAM ? "AM" : "PM") – \(e) \(endAM ? "AM" : "PM")"
    }

    /// "4:05" style countdown text. Ignores sign; callers add "+" for overtime.
    nonisolated static func clockTime(from seconds: Int) -> String {
        let absoluteSeconds = abs(seconds)
        let minutes = absoluteSeconds / 60
        let remainingSeconds = absoluteSeconds % 60

        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    static func shortClockTime(from date: Date) -> String {
        shortClockFormatter.string(from: date)
    }

    /// "5 min", "1 min 30 sec", "45 sec".
    nonisolated static func durationText(from seconds: Int) -> String {
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
    nonisolated static func spokenDuration(from seconds: Int) -> String {
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
    nonisolated static func scheduleDeltaText(from deltaSeconds: Int) -> String {
        if abs(deltaSeconds) < 1 { return "ON PLAN" }
        return "\(clockTime(from: deltaSeconds)) \(deltaSeconds < 0 ? "AHEAD" : "BEHIND")"
    }
}
