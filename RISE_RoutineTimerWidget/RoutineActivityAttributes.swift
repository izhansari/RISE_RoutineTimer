//
//  RoutineActivityAttributes.swift
//  Shared between the app (which starts, updates and ends the activity) and
//  the widget extension (which draws the Lock Screen banner and the Dynamic
//  Island). It is a member of both targets via a membership exception on the
//  widget folder — see the pbxproj — so there is exactly one copy.
//
//  Everything the widget needs is in the content state. It cannot import the
//  app, so no engine, no theme enum, no formatting helpers: dates it can run
//  timers from, strings it can print, and a theme *name* it maps to a colour
//  with its own small table.
//

import ActivityKit
import Foundation

nonisolated struct RoutineActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var stepTitle: String
        var stepIcon: String
        /// 1-based, for "STEP 3 OF 16".
        var stepIndex: Int
        var stepCount: Int
        /// The widget counts down from `stepStart` to `stepEnd` on its own —
        /// no updates needed while a step runs.
        var stepStart: Date
        var stepEnd: Date
        var autoNext: Bool
        var nextTitle: String?
        var projectedEnd: Date
        /// Position through the whole routine by the plan, 0…1.
        var planProgress: Double
        var isPaused: Bool
        /// Shown instead of a running countdown while paused.
        var pausedRemainingSeconds: Int
        /// `FillTheme.rawValue`; the widget keeps its own colour table.
        var theme: String
    }

    var routineName: String
}
