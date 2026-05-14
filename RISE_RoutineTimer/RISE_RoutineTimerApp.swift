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
    init() {
        registerBundledFonts()
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
        }
        .modelContainer(sharedModelContainer)
    }
}

private func registerBundledFonts() {
    guard let url = Bundle.main.url(forResource: "Fake Receipt", withExtension: "otf") else {
        return
    }

    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}
