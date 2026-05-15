import SwiftData
import SwiftUI

struct StepEditorView: View {
    @Bindable var step: RoutineStep

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $step.title)
                Toggle("Auto-next", isOn: $step.autoNext)
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
        }
        .navigationTitle(step.title.isEmpty ? "Step" : step.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var minutesBinding: Binding<Int> {
        Binding {
            step.durationSeconds / 60
        } set: { newMinutes in
            let seconds = step.durationSeconds % 60
            step.durationSeconds = max(1, newMinutes * 60 + seconds)
        }
    }

    private var secondsBinding: Binding<Int> {
        Binding {
            step.durationSeconds % 60
        } set: { newSeconds in
            let minutes = step.durationSeconds / 60
            step.durationSeconds = max(1, minutes * 60 + newSeconds)
        }
    }
}
