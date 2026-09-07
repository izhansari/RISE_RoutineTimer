//
//  RoutineListView.swift
//  RISE_RoutineTimer
//
//  The "Routine" tab: the step list, the finish-by target, and housekeeping.
//

import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(TargetSchedule.targetKey) private var targetMinutes = TargetSchedule.none
    @AppStorage(TargetSchedule.reminderKey) private var reminderEnabled = false
    @AppStorage(MorningSettings.targetWakeKey) private var targetWakeMinutes = MorningSettings.defaultTargetWakeMinutes
    @AppStorage(MorningSettings.snoozeBudgetKey) private var snoozeBudget = MorningSettings.defaultSnoozeBudget
    @AppStorage(MorningSettings.activationBudgetKey) private var activationBudget = MorningSettings.defaultActivationBudget
    @State private var path = NavigationPath()
    @State private var confirmingRestore = false

    let steps: [RoutineStep]

    private var plannedSeconds: Int { steps.reduce(0) { $0 + $1.durationSeconds } }
    private var schedule: TargetSchedule { TargetSchedule(targetMinutesAfterMidnight: targetMinutes) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                stepsSection
                wakeGoalSection
                targetSection
            }
            .navigationTitle("Routine")
            .navigationDestination(for: RoutineStep.self) { step in
                StepEditorView(step: step)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: addStep) { Label("Add Step", systemImage: "plus") }
                        Divider()
                        Button { confirmingRestore = true } label: {
                            Label("Restore Starter Routine", systemImage: "arrow.counterclockwise")
                        }
                        #if DEBUG
                        Divider()
                        Button {
                            DebugSeed.populate(
                                context: modelContext,
                                steps: steps,
                                settings: MorningSettings(targetWakeMinutes: targetWakeMinutes)
                            )
                        } label: {
                            Label("Seed Sample History", systemImage: "wand.and.stars")
                        }
                        Button(role: .destructive) {
                            DebugSeed.clear(context: modelContext)
                        } label: {
                            Label("Clear All History", systemImage: "trash")
                        }
                        #endif
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Routine actions")
                }
            }
            .confirmationDialog("Replace your routine with the starter one?", isPresented: $confirmingRestore, titleVisibility: .visible) {
                Button("Replace Routine", role: .destructive) { restoreStarterRoutine() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current steps will be deleted. History is kept.")
            }
            .onChange(of: targetMinutes) { _, _ in syncReminder() }
            .onChange(of: reminderEnabled) { _, _ in syncReminder() }
            .onChange(of: plannedSeconds) { _, _ in syncReminder() }
        }
    }

    // MARK: - Sections

    private var stepsSection: some View {
        Section {
            ForEach(steps) { step in
                NavigationLink(value: step) {
                    RoutineStepRow(step: step)
                }
                .swipeActions(edge: .leading) {
                    Button { duplicate(step) } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(.blue)
                }
            }
            .onDelete(perform: deleteSteps)
            .onMove(perform: moveSteps)

            Button(action: addStep) {
                Label("Add Step", systemImage: "plus")
            }
        } footer: {
            if plannedSeconds > 0 {
                Text("Total: \(TimeFormatting.durationText(from: plannedSeconds))")
            }
        }
    }

    /// The wake goal and the weekly allowances the Today tab scores against.
    private var wakeGoalSection: some View {
        Section {
            DatePicker("Wake up by", selection: wakeGoalBinding, displayedComponents: .hourAndMinute)

            Stepper(value: $snoozeBudget, in: 0...600, step: 15) {
                LabeledContent("Snooze budget", value: "\(snoozeBudget) min / week")
            }

            Stepper(value: $activationBudget, in: 0...600, step: 15) {
                LabeledContent("Activation budget", value: "\(activationBudget) min / week")
            }
        } header: {
            Text("Morning goal")
        } footer: {
            Text("Snooze is time past your wake goal. Activation is time between waking and starting. Each week's overruns are drawn against these budgets on the Today tab.")
        }
    }

    private var wakeGoalBinding: Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date())
                .addingTimeInterval(TimeInterval(targetWakeMinutes * 60))
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            targetWakeMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private var targetSection: some View {
        Section {
            Toggle("Finish by a set time", isOn: targetEnabledBinding)
            if schedule.isSet {
                DatePicker("Finish by", selection: targetDateBinding, displayedComponents: .hourAndMinute)
                Toggle("Remind me when it's time to start", isOn: $reminderEnabled)
            }
        } header: {
            Text("Target")
        } footer: {
            if let startBy = schedule.startByDate(on: Date(), plannedSeconds: plannedSeconds) {
                Text("Start by \(TimeFormatting.shortClockTime(from: startBy)) to finish on time with the current \(TimeFormatting.durationText(from: plannedSeconds)) plan.")
            } else {
                Text("Set the time you need to be done, and RISE will tell you when to start.")
            }
        }
    }

    // MARK: - Bindings

    private var targetEnabledBinding: Binding<Bool> {
        Binding {
            schedule.isSet
        } set: { enabled in
            targetMinutes = enabled ? 7 * 60 + 30 : TargetSchedule.none
        }
    }

    private var targetDateBinding: Binding<Date> {
        Binding {
            schedule.targetDate(on: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            targetMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    // MARK: - Actions

    private func syncReminder() {
        guard reminderEnabled, let target = schedule.targetDate(on: Date()) else {
            RoutineNotificationManager.scheduleDailyReminder(at: nil, targetText: "")
            return
        }
        RoutineNotificationManager.scheduleDailyReminder(
            at: schedule.startByComponents(plannedSeconds: plannedSeconds),
            targetText: TimeFormatting.shortClockTime(from: target)
        )
    }

    private func addStep() {
        let step = RoutineStep(
            title: "New Step",
            durationSeconds: 5 * 60,
            autoNext: true,
            notes: "",
            sortOrder: nextSortOrder
        )
        modelContext.insert(step)
        saveChanges()
        path.append(step)
    }

    private func duplicate(_ source: RoutineStep) {
        var reordered = steps
        let copy = RoutineStep(
            title: source.title,
            icon: source.icon,
            durationSeconds: source.durationSeconds,
            autoNext: source.autoNext,
            notes: source.notes,
            sortOrder: nextSortOrder
        )
        modelContext.insert(copy)
        if let index = reordered.firstIndex(where: { $0 === source }) {
            reordered.insert(copy, at: index + 1)
        } else {
            reordered.append(copy)
        }
        withAnimation {
            renumberSortOrder(for: reordered)
            saveChanges()
        }
    }

    private func restoreStarterRoutine() {
        withAnimation {
            for step in steps { modelContext.delete(step) }
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
    }

    private var nextSortOrder: Int {
        (steps.map(\.sortOrder).max() ?? -1) + 1
    }

    private func deleteSteps(at offsets: IndexSet) {
        let stepsToDelete = offsets.map { steps[$0] }
        withAnimation {
            for step in stepsToDelete { modelContext.delete(step) }
            let remaining = steps.filter { step in !stepsToDelete.contains { $0 === step } }
            renumberSortOrder(for: remaining)
            saveChanges()
        }
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        var reordered = steps
        reordered.move(fromOffsets: source, toOffset: destination)
        withAnimation {
            renumberSortOrder(for: reordered)
            saveChanges()
        }
    }

    private func renumberSortOrder(for orderedSteps: [RoutineStep]) {
        for (index, step) in orderedSteps.enumerated() {
            step.sortOrder = index
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Could not save routine changes: \(error)")
        }
    }
}

private struct RoutineStepRow: View {
    let step: RoutineStep

    var body: some View {
        HStack(spacing: 12) {
            if !step.icon.isEmpty {
                Text(step.icon)
                    .font(.system(size: 26))
                    .frame(width: 36)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(analogFont(22))

                HStack(spacing: 10) {
                    Text(TimeFormatting.durationText(from: step.durationSeconds))
                        .font(analogFont(16))

                    if !step.autoNext {
                        Text("MANUAL")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
