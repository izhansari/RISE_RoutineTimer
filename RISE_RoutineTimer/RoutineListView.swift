//
//  RoutineListView.swift
//  RISE_RoutineTimer
//
//  The editor tab: add, delete, reorder, and open details for each step.
//

import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext

    let steps: [RoutineStep]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(steps) { step in
                        NavigationLink {
                            StepEditorView(step: step)
                        } label: {
                            RoutineStepRow(step: step)
                        }
                    }
                    .onDelete(perform: deleteSteps)
                    .onMove(perform: moveSteps)
                } footer: {
                    Text("Tip: drag steps while editing to change the order of your routine.")
                }
            }
            .navigationTitle("Routine")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: addStep) {
                        Label("Add Step", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func addStep() {
        let nextSortOrder = (steps.map(\.sortOrder).max() ?? -1) + 1
        let step = RoutineStep(
            title: "New Step",
            durationSeconds: 5 * 60,
            autoNext: true,
            notes: "",
            sortOrder: nextSortOrder
        )

        withAnimation {
            modelContext.insert(step)
            saveChanges()
        }
    }

    private func deleteSteps(at offsets: IndexSet) {
        let stepsToDelete = offsets.map { steps[$0] }

        withAnimation {
            for step in stepsToDelete {
                modelContext.delete(step)
            }

            let remainingSteps = steps.filter { step in
                !stepsToDelete.contains { $0 === step }
            }
            renumberSortOrder(for: remainingSteps)
            saveChanges()
        }
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        var reorderedSteps = steps
        reorderedSteps.move(fromOffsets: source, toOffset: destination)

        withAnimation {
            renumberSortOrder(for: reorderedSteps)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(step.title)
                .font(.headline)

            HStack(spacing: 12) {
                Label(TimeFormatting.durationText(from: step.durationSeconds), systemImage: "clock")
                Label(step.autoNext ? "Auto-next" : "Manual next", systemImage: step.autoNext ? "arrow.right.circle" : "hand.tap")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
