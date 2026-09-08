//
//  RoutineListView.swift
//  RISE_RoutineTimer
//
//  The full step list: reorder, swipe-delete, duplicate, restore the starter
//  routine. Presented as a sheet from Settings. Day-to-day editing does not
//  come here — tapping a step on the Run tab edits it in place — so this is
//  the occasional-use tool, not the front door.
//

import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var path = NavigationPath()
    @State private var confirmingRestore = false

    let steps: [RoutineStep]

    private var plannedSeconds: Int { steps.reduce(0) { $0 + $1.durationSeconds } }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(steps) { step in
                        NavigationLink(value: StepEditRequest(step: step)) {
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

                Section {
                    Button(role: .destructive) { confirmingRestore = true } label: {
                        Label("Restore Starter Routine", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: StepEditRequest.self) { request in
                StepEditorView(request: request)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Replace your routine with the starter one?", isPresented: $confirmingRestore, titleVisibility: .visible) {
                Button("Replace Routine", role: .destructive) { restoreStarterRoutine() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current steps will be deleted. History is kept.")
            }
        }
    }

    // MARK: - Actions

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
        path.append(StepEditRequest(step: step, isNew: true))
    }

    private func duplicate(_ source: RoutineStep) {
        var reordered = steps
        let copy = RoutineStep(
            title: source.title,
            icon: source.icon,
            durationSeconds: source.durationSeconds,
            autoNext: source.autoNext,
            notes: source.notes,
            autoShowNotes: source.autoShowNotes,
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
                    .font(.system(size: 24))
                    .frame(width: 32)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(analogFont(19))

                HStack(spacing: 10) {
                    Text(TimeFormatting.durationText(from: step.durationSeconds))
                        .font(analogFont(14))

                    if !step.autoNext {
                        Text("MANUAL")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
