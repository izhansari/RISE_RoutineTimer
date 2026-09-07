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
    @AppStorage("seededRoutineVersion") private var seededRoutineVersion = 0

    /// Today is the landing screen: the morning starts before the routine does.
    @State private var selectedTab: Tab = .today

    private enum Tab: Hashable { case today, run, history, settings }

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

            HistoryView(steps: steps)
                .tabItem {
                    Label("History", systemImage: "chart.xyaxis.line")
                }
                .tag(Tab.history)

            SettingsView(steps: steps)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .task {
            seedStarterRoutineIfNeeded()
            repairDuplicateStepIDs()
            // Asking here means the prompt shows over the idle screen, never over a running timer.
            await RoutineNotificationManager.requestPermissionIfNeeded()
        }
    }

    /// Seeds the routine, and re-seeds it when `starterRoutineVersion` moves.
    ///
    /// A version bump **replaces** whatever is saved, which is how the owner's
    /// routine gets loaded onto a device that already has an older one. That
    /// also means it discards edits made on the device, so the version is only
    /// bumped when a reload has actually been asked for.
    ///
    /// A run already in progress is unaffected: the engine freezes its steps
    /// when it starts.
    private func seedStarterRoutineIfNeeded() {
        guard seededRoutineVersion < RoutineStep.starterRoutineVersion else { return }
        seededRoutineVersion = RoutineStep.starterRoutineVersion

        let existing = (try? modelContext.fetch(FetchDescriptor<RoutineStep>())) ?? []
        for step in existing {
            modelContext.delete(step)
        }

        for (index, seed) in RoutineStep.starterRoutine.enumerated() {
            modelContext.insert(RoutineStep(
                title: seed.title,
                icon: seed.icon,
                durationSeconds: seed.durationSeconds,
                autoNext: seed.autoNext,
                notes: seed.notes,
                sortOrder: index
            ))
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
