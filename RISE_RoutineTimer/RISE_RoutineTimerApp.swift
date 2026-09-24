//
//  RISE_RoutineTimerApp.swift
//  RISE_RoutineTimer
//
//  Created by Izhan S Ansari on 5/13/26.
//

import SwiftUI
import SwiftData
import CoreText
import UIKit
import UserNotifications

@main
struct RISE_RoutineTimerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // The engine restores any in-progress run from disk, and the coordinator
    // is attached before the first tick so alerts are never missed.
    @State private var engine: RoutineEngine
    @State private var navigation = AppNavigation()
    private let alertCoordinator: RoutineAlertCoordinator
    /// Held for the life of the app: the notification centre keeps only a
    /// weak reference to its delegate.
    private let notificationPresenter = NotificationPresenter()

    private let sharedModelContainer: ModelContainer

    init() {
        registerBundledFonts()

        let schema = Schema([RoutineStep.self, RoutineSession.self, MorningLog.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        let engine = RoutineEngine()
        let recorder = SessionRecorder(context: sharedModelContainer.mainContext)
        _engine = State(initialValue: engine)
        let morningLog = MorningLogStore(context: sharedModelContainer.mainContext)
        alertCoordinator = RoutineAlertCoordinator(
            engine: engine,
            // Starting the routine means you are up, whether or not "I'm
            // awake" was tapped first. (The store ignores a night run.)
            runStarted: { start, kind in
                morningLog.recordWakeImplied(byRoutineStartingAt: start, kind: kind, settings: .stored())
            },
            recordSession: { recorder.record($0) }
        )

        // App Intents are built by the system, outside the view tree; this
        // is how they reach the same engine and store the views use.
        let navigation = AppNavigation()
        _navigation = State(initialValue: navigation)
        AppServices.engine = engine
        AppServices.container = sharedModelContainer
        AppServices.navigation = navigation

        UNUserNotificationCenter.current().delegate = notificationPresenter
        // Scheduled from launch, not only from Settings, so it exists
        // without anyone having to go and switch it on.
        RoutineNotificationManager.syncNightReminder()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .environment(navigation)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                alertCoordinator.applicationDidBecomeActive()
            } else {
                // Run saves are queued off the main thread; this is the last
                // moment before iOS may kill us, so make sure they landed.
                engine.flushToDisk()
            }
            syncIdleTimer()
        }
        .onChange(of: engine.hasActiveRun, initial: true) { _, _ in
            syncIdleTimer()
        }
    }

    /// The screen stays on while a routine is running — wherever in the app
    /// you are. This used to live on the Run tab and switched itself off in
    /// `onDisappear`, so glancing at Today mid-routine let the phone sleep.
    private func syncIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = engine.hasActiveRun && scenePhase == .active
    }
}

private func registerBundledFonts() {
    guard let url = Bundle.main.url(forResource: "Fake Receipt", withExtension: "otf") else {
        return
    }

    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}
