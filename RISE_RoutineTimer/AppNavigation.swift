//
//  AppNavigation.swift
//  RISE_RoutineTimer
//
//  Where the app is, as an object rather than a view's private state, so
//  something outside the view tree — an App Intent — can open the routine
//  screen after starting a routine.
//
//  There is no tab bar. Today is the only home screen; the routine screen
//  (what was the Run tab) opens over it full-screen, and History and
//  Settings are pushed from it. Three buttons in Today's header reach all
//  three.
//

import Foundation
import Observation
import SwiftData

@Observable
final class AppNavigation {
    /// The routine screen — the step lists, Start, and the timer — shown
    /// full-screen over Today.
    var showsRoutine = false

    /// History is no longer a tab — it is pushed from the week chart on
    /// Today, which is the thing you were already looking at when you wanted
    /// more of it. This is how anything else (the Run tab's streak badge)
    /// asks for it.
    var showsHistory = false
    /// Settings is a gear in Today's header rather than a tab: it is a place
    /// you visit occasionally, and the tab bar is for the two things you do
    /// every morning.
    var showsSettings = false
    /// Which routine History opens on. ALL MORNINGS › asks for the morning;
    /// the Run tab's streak badge asks for whichever routine it is showing.
    var historyKind: RoutineKind = .morning
    /// Which routine Settings leads with — its goal section comes first.
    var settingsKind: RoutineKind = .morning

    /// Opens the routine screen on one routine's list. The header buttons
    /// pass the mode Today is in, so the night page opens on NIGHT and the
    /// morning page on MORNING. A run in progress shows the run whatever
    /// this says, and the list then follows the run's kind by itself.
    func openRoutines(kind: RoutineKind) {
        UserDefaults.standard.set(kind.rawValue, forKey: RoutineKind.selectionKey)
        showsRoutine = true
    }

    func openSettings(kind: RoutineKind) {
        settingsKind = kind
        showsSettings = true
    }

    func openHistory(kind: RoutineKind = .morning) {
        showsRoutine = false
        historyKind = kind
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
