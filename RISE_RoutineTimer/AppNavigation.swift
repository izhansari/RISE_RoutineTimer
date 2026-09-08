//
//  AppNavigation.swift
//  RISE_RoutineTimer
//
//  Which tab is showing, as an object rather than a view's private state, so
//  something outside the view tree — an App Intent — can put the app on the
//  Run tab after starting a routine.
//

import Observation
import SwiftData

@Observable
final class AppNavigation {
    enum Tab: Hashable { case today, run, history, settings }

    var selectedTab: Tab = .today
}

/// The long-lived objects an App Intent needs. Intents are created by the
/// system, not by the view tree, so they cannot receive these through the
/// environment; the app registers them once in `RISE_RoutineTimerApp.init`.
@MainActor
enum AppServices {
    static var engine: RoutineEngine?
    static var container: ModelContainer?
    static var navigation: AppNavigation?
}
