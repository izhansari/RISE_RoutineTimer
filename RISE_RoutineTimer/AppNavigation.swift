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
    enum Tab: Hashable { case today, run }

    var selectedTab: Tab = .today

    /// History is no longer a tab — it is pushed from the week chart on
    /// Today, which is the thing you were already looking at when you wanted
    /// more of it. This is how anything else (the Run tab's streak badge)
    /// asks for it.
    var showsHistory = false
    /// Settings is a gear in Today's header rather than a tab: it is a place
    /// you visit occasionally, and the tab bar is for the two things you do
    /// every morning.
    var showsSettings = false

    func openHistory() {
        selectedTab = .today
        showsHistory = true
    }
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
