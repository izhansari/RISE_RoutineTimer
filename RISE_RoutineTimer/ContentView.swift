//
//  ContentView.swift
//  RISE_RoutineTimer
//
//  The root screen owns the saved routine query and shows the two main tabs.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoutineStep.sortOrder, order: .forward) private var steps: [RoutineStep]

    var body: some View {
        TabView {
            RoutineTimerView(steps: steps)
                .tabItem {
                    Label("Run", systemImage: "timer")
                }

            RoutineListView(steps: steps)
                .tabItem {
                    Label("Edit", systemImage: "list.bullet")
                }
        }
        .task {
            seedStarterRoutineIfNeeded()
        }
    }

    private func seedStarterRoutineIfNeeded() {
        guard steps.isEmpty else {
            return
        }

        for (index, seed) in RoutineStep.starterRoutine.enumerated() {
            let step = RoutineStep(
                title: seed.title,
                durationSeconds: seed.durationSeconds,
                autoNext: seed.autoNext,
                notes: seed.notes,
                sortOrder: index
            )

            modelContext.insert(step)
        }

        saveChanges()
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Could not save starter routine: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: RoutineStep.self, inMemory: true)
}
