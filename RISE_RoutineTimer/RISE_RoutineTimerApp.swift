//
//  RISE_RoutineTimerApp.swift
//  RISE_RoutineTimer
//
//  Created by Izhan S Ansari on 5/13/26.
//

import SwiftUI
import SwiftData

@main
struct RISE_RoutineTimerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
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
