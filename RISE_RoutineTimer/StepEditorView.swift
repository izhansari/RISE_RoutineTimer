//
//  StepEditorView.swift
//  RISE_RoutineTimer
//
//  The detail form for editing one saved routine step.
//

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
                Stepper(value: minutesBinding, in: 0...180) {
                    LabeledContent("Minutes", value: "\(step.durationSeconds / 60)")
                }

                Stepper(value: secondsBinding, in: 0...59) {
                    LabeledContent("Seconds", value: "\(step.durationSeconds % 60)")
                }

                Text(TimeFormatting.durationText(from: step.durationSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notes") {
                TextEditor(text: $step.notes)
                    .frame(minHeight: 140)
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
