import SwiftData
import SwiftUI

struct StepEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var step: RoutineStep
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    TextField("", text: iconBinding, prompt: Text("🙂"))
                        .font(.system(size: 26))
                        .multilineTextAlignment(.center)
                        .frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Icon emoji")
                    TextField("Title", text: $step.title)
                        .font(analogFont(17))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                }
                Toggle("Auto-next", isOn: $step.autoNext)
            } header: {
                Text("Task")
            } footer: {
                Text("Auto-next moves on when time is up. Turn it off for steps you want to finish at your own pace.")
            }

            Section("Duration") {
                HStack(spacing: 0) {
                    Picker("Minutes", selection: minutesBinding) {
                        ForEach(0..<180) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Seconds", selection: secondsBinding) {
                        ForEach(0..<60) { s in
                            Text(String(format: "%02d sec", s)).tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .frame(height: 150)
            }

            Section("Notes") {
                TextEditor(text: $step.notes)
                    .frame(minHeight: 120)
            }

            Section {
                Button("Delete Step", role: .destructive) { confirmingDelete = true }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(step.title.isEmpty ? "Step" : step.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this step?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Step", role: .destructive) { deleteStep() }
            Button("Keep", role: .cancel) {}
        }
        .onDisappear {
            if step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                step.title = RoutineStep.untitled
            }
            try? modelContext.save()
        }
    }

    private var iconBinding: Binding<String> {
        Binding {
            step.icon
        } set: { newValue in
            step.icon = RoutineStep.normalizedIcon(newValue)
        }
    }

    private func deleteStep() {
        modelContext.delete(step)
        try? modelContext.save()
        dismiss()
    }

    private var minutesBinding: Binding<Int> {
        Binding {
            step.durationSeconds / 60
        } set: { newMinutes in
            let seconds = step.durationSeconds % 60
            step.durationSeconds = max(RoutineStep.minimumDurationSeconds, newMinutes * 60 + seconds)
        }
    }

    private var secondsBinding: Binding<Int> {
        Binding {
            step.durationSeconds % 60
        } set: { newSeconds in
            let minutes = step.durationSeconds / 60
            step.durationSeconds = max(RoutineStep.minimumDurationSeconds, minutes * 60 + newSeconds)
        }
    }
}
