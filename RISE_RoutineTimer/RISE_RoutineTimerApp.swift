//
//  RISE_RoutineTimerApp.swift
//  RISE_RoutineTimer
//
//  Created by Izhan S Ansari on 5/13/26.
//

import SwiftUI
import SwiftData
import CoreText

@main
struct RISE_RoutineTimerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // The engine restores any in-progress run from disk, and the coordinator
    // is attached before the first tick so alerts are never missed.
    @State private var engine: RoutineEngine
    private let alertCoordinator: RoutineAlertCoordinator

    init() {
        registerBundledFonts()
        let engine = RoutineEngine()
        _engine = State(initialValue: engine)
        alertCoordinator = RoutineAlertCoordinator(engine: engine)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RoutineStep.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                alertCoordinator.applicationDidBecomeActive()
            }
        }
    }
}

private func registerBundledFonts() {
    guard let url = Bundle.main.url(forResource: "Fake Receipt", withExtension: "otf") else {
        return
    }

    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}
