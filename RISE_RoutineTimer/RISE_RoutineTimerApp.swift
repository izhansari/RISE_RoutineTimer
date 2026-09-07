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
        alertCoordinator = RoutineAlertCoordinator(engine: engine) { recorder.record($0) }
    }

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
