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
    @AppStorage("hasSeededStarterRoutine") private var hasSeededStarterRoutine = false

    /// Today is the landing screen: the morning starts before the routine does.
    @State private var selectedTab: Tab = .today

    private enum Tab: Hashable { case today, run, routine, history }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(steps: steps, onStartRoutine: { selectedTab = .run })
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(Tab.today)

            RoutineTimerView(steps: steps)
                .tabItem {
                    Label("Run", systemImage: "timer")
                }
                .tag(Tab.run)

            RoutineListView(steps: steps)
                .tabItem {
                    Label("Routine", systemImage: "list.bullet")
                }
                .tag(Tab.routine)

            HistoryView(steps: steps)
                .tabItem {
                    Label("History", systemImage: "chart.xyaxis.line")
                }
                .tag(Tab.history)
        }
        .task {
            seedStarterRoutineIfNeeded()
            repairDuplicateStepIDs()
            // Asking here means the prompt shows over the idle screen, never over a running timer.
            await RoutineNotificationManager.requestPermissionIfNeeded()
        }
    }

    /// Seeds once per install. Deleting every step on purpose stays deleted.
    private func seedStarterRoutineIfNeeded() {
        guard !hasSeededStarterRoutine else { return }
        hasSeededStarterRoutine = true

        let existing = (try? modelContext.fetchCount(FetchDescriptor<RoutineStep>())) ?? 0
        guard existing == 0 else { return }

        for (index, seed) in RoutineStep.starterRoutine.enumerated() {
            let step = RoutineStep(
                title: seed.title,
                icon: seed.icon,
                durationSeconds: seed.durationSeconds,
                autoNext: seed.autoNext,
                notes: seed.notes,
                sortOrder: index
            )
            modelContext.insert(step)
        }

        saveChanges()
    }

    /// Steps created before `stepID` existed may share one migrated default.
    private func repairDuplicateStepIDs() {
        var seen = Set<UUID>()
        var changed = false
        for step in steps {
            if seen.contains(step.stepID) {
                step.stepID = UUID()
                changed = true
            }
            seen.insert(step.stepID)
        }
        if changed { saveChanges() }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Could not save routine: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [RoutineStep.self, RoutineSession.self, MorningLog.self], inMemory: true)
        .environment(RoutineEngine(store: nil))
}
