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

    static func clockTime(from seconds: Int) -> String {
        let absoluteSeconds = abs(seconds)
        let minutes = absoluteSeconds / 60
        let remainingSeconds = absoluteSeconds % 60

        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    static func shortClockTime(from date: Date) -> String {
        shortClockFormatter.string(from: date)
    }

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
}
