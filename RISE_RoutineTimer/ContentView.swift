//
//  ContentView.swift
//  RISE_RoutineTimer
//
//  The root screen owns the saved routine query and shows Today, with the
//  routine screen full-screen over it when asked for. There is no tab bar.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    /// Every step of both routines. The Run tab shows one routine at a time
    /// (`steps.routine(_:)`); Today, History and the morning goal only ever
    /// mean the morning one.
    @Query(sort: \RoutineStep.sortOrder, order: .forward) private var steps: [RoutineStep]
    @AppStorage("seededRoutineVersion") private var seededRoutineVersion = 0
    @AppStorage("seededNightRoutineVersion") private var seededNightRoutineVersion = 0

    /// Today is the only home screen. Whether the routine screen is up lives
    /// in `AppNavigation`, so an App Intent that starts a routine can open it.
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation

        // No tab bar: Today is home, and the routine screen opens over it.
        TodayView(allSteps: steps, onStartRoutine: { navigation.showsRoutine = true })
        .fullScreenCover(isPresented: $navigation.showsRoutine) {
            RoutineTimerView(allSteps: steps)
        }
        .task {
            seedStarterRoutineIfNeeded()
            seedNightRoutineIfNeeded()
            repairDuplicateStepIDs()
            backfillWakeGoals()
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
        // Only the morning: a reload of the owner's morning routine must not
        // take the night sketch with it.
        for step in existing.routine(.morning) {
            modelContext.delete(step)
        }

        insertStarter(.morning)
        saveChanges()
    }

    /// Lays down a first draft of the night routine, once, on a device that
    /// has never had night steps. It is a sketch to edit, so unlike the
    /// morning starter it is never re-seeded over the top of what is there.
    private func seedNightRoutineIfNeeded() {
        guard seededNightRoutineVersion < RoutineStep.nightStarterRoutineVersion else { return }
        seededNightRoutineVersion = RoutineStep.nightStarterRoutineVersion

        let existing = (try? modelContext.fetch(FetchDescriptor<RoutineStep>())) ?? []
        guard existing.routine(.night).isEmpty else { return }

        insertStarter(.night)
        saveChanges()
    }

    private func insertStarter(_ kind: RoutineKind) {
        for (index, seed) in RoutineStep.starterRoutine(for: kind).enumerated() {
            modelContext.insert(RoutineStep(
                title: seed.title,
                icon: seed.icon,
                durationSeconds: seed.durationSeconds,
                autoNext: seed.autoNext,
                notes: seed.notes,
                sortOrder: index,
                kind: kind
            ))
        }
    }

    /// Mornings logged before the goal was stored on them get the goal that
    /// is set now.
    ///
    /// It is a guess — the real goal on those days was not recorded — but it
    /// is exactly the number those mornings were already being scored
    /// against, so nothing changes today. What it buys is that the *next*
    /// time the goal moves, those mornings keep the old one instead of
    /// silently following along. See `MorningLog.goalMinutes`.
    private func backfillWakeGoals() {
        let logs = (try? modelContext.fetch(FetchDescriptor<MorningLog>())) ?? []
        let goal = MorningSettings.stored().targetWakeMinutes
        var changed = false
        for log in logs where log.goalMinutes == nil {
            log.goalMinutes = goal
            changed = true
        }
        if changed { saveChanges() }
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
        .environment(AppNavigation())
}
