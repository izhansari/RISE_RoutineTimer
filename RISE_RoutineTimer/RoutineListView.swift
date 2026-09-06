import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var path = NavigationPath()

    let steps: [RoutineStep]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(steps) { step in
                        NavigationLink(value: step) {
                            RoutineStepRow(step: step)
                        }
                    }
                    .onDelete(perform: deleteSteps)
                    .onMove(perform: moveSteps)
                } footer: {
                    let total = steps.reduce(0) { $0 + $1.durationSeconds }
                    if total > 0 {
                        Text("Total: \(TimeFormatting.durationText(from: total))")
                    }
                }
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
        modelContext.insert(step)
        saveChanges()
        path.append(step)
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
        .padding(.vertical, 6)
    }
}
