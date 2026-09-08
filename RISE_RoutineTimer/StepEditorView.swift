//
//  StepEditorView.swift
//  RISE_RoutineTimer
//
//  The per-step form. It edits a *draft*, not the saved step: nothing reaches
//  SwiftData until Save. The earlier version bound the form straight to the
//  model, so every wheel tick and keystroke was already persisted and there
//  was no way to back out of an accidental change.
//

import SwiftData
import SwiftUI

/// What to open in the editor. `isNew` marks a step that was inserted only so
/// it could be edited — Cancel removes it again instead of leaving a stray
/// "New Step" in the routine.
struct StepEditRequest: Hashable, Identifiable {
    let step: RoutineStep
    var isNew = false

    var id: PersistentIdentifier { step.persistentModelID }
}

struct StepEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let step: RoutineStep
    let isNew: Bool

    @State private var draft: Draft
    private let initial: Draft
    @State private var confirmingDelete = false
    @State private var confirmingDiscard = false
    @State private var pickingIcon = false
    /// Pulse the missing field red when Add / Save is pressed without a
    /// title or icon — only the missing one, so a filled-in title with no
    /// icon points straight at the icon box. The button stays tappable so
    /// the tap can *show* what is missing, instead of a greyed-out control
    /// that explains nothing.
    @State private var isFlashingTitle = false
    @State private var isFlashingIcon = false
    @FocusState private var titleFocused: Bool

    init(step: RoutineStep, isNew: Bool = false) {
        self.step = step
        self.isNew = isNew
        var draft = Draft(step)
        if isNew {
            // Show the placeholder, not a "New Step" to delete first.
            draft.title = ""
        }
        initial = draft
        _draft = State(initialValue: draft)
    }

    init(request: StepEditRequest) {
        self.init(step: request.step, isNew: request.isNew)
    }

    /// The editable copy. Compared against the step to know whether Cancel
    /// needs to ask first.
    nonisolated struct Draft: Equatable {
        var icon: String
        var title: String
        var autoNext: Bool
        var durationSeconds: Int
        var notes: String
        var autoShowNotes: Bool

        init(_ step: RoutineStep) {
            icon = step.icon
            title = step.title
            autoNext = step.autoNext
            durationSeconds = step.durationSeconds
            notes = step.notes
            autoShowNotes = step.autoShowNotes
        }
    }

    private var hasChanges: Bool { draft != initial }

    /// A step needs a name and an icon before it can be saved; Save stays
    /// disabled until both are there.
    private var canSave: Bool { !titleMissing && !iconMissing }
    private var titleMissing: Bool { draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var iconMissing: Bool { draft.icon.isEmpty }

    private var requiredHint: String? {
        switch (titleMissing, iconMissing) {
        case (true, true): return "Give the step a name and pick an icon to save it."
        case (true, false): return "Give the step a name to save it."
        case (false, true): return "Pick an icon to save it."
        case (false, false): return nil
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Button {
                        pickingIcon = true
                    } label: {
                        Group {
                            if draft.icon.isEmpty {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(draft.icon).font(.system(size: 26))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(
                            isFlashingIcon ? Color.red.opacity(0.3) : Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.red, lineWidth: isFlashingIcon ? 2 : 0)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(draft.icon.isEmpty ? "Choose an icon" : "Icon \(draft.icon), change it")

                    TextField("Title (required)", text: $draft.title)
                        .font(analogFont(17))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($titleFocused)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(isFlashingTitle ? 0.22 : 0))
                        )
                }
                Toggle("Auto-next", isOn: $draft.autoNext)
            } header: {
                HStack(spacing: 3) {
                    Text("Task")
                    Text("*").foregroundStyle(.red)
                }
            } footer: {
                Text(requiredHint ?? "Auto-next moves on when time is up. Turn it off for steps you want to finish at your own pace.")
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

            Section {
                TextEditor(text: $draft.notes)
                    .font(.system(size: 16))
                    .autocorrectionDisabled()
                    .frame(minHeight: 120)
                Toggle("Open automatically", isOn: $draft.autoShowNotes)
            } header: {
                Text("Notes")
            } footer: {
                Text("When on, this note opens by itself as the step starts. You can also add or edit notes while the routine is running.")
            }

            if !isNew {
                Section {
                    Button("Delete Step", role: .destructive) { confirmingDelete = true }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(isNew ? "New Step" : (step.title.isEmpty ? "Step" : step.title))
        .navigationBarTitleDisplayMode(.inline)
        // Both ways out go through Cancel or Save: no back button on a push,
        // no swipe-away on a sheet once something has changed.
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(hasChanges || isNew)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isNew {
                    Button { cancel() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Discard new step")
                } else {
                    Button("Cancel") { cancel() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") { save() }
                    .fontWeight(.semibold)
                    .opacity(canSave ? 1 : 0.4)
            }
        }
        .confirmationDialog("Delete this step?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Step", role: .destructive) { deleteStep() }
            Button("Keep", role: .cancel) {}
        }
        .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button(isNew ? "Discard Step" : "Discard Changes", role: .destructive) { discard() }
            Button("Keep Editing", role: .cancel) {}
        }
        .sheet(isPresented: $pickingIcon) {
            GlyphPickerView(selection: iconBinding)
        }
    }

    // MARK: - Actions

    private func cancel() {
        if hasChanges {
            confirmingDiscard = true
        } else {
            discard()
        }
    }

    /// Throws the draft away. A step inserted just for this editor goes too.
    private func discard() {
        if isNew {
            modelContext.delete(step)
            try? modelContext.save()
        }
        dismiss()
    }

    private func save() {
        guard canSave else {
            flashRequiredFields()
            return
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        step.icon = RoutineStep.normalizedIcon(draft.icon)
        step.title = title.isEmpty ? RoutineStep.untitled : title
        step.autoNext = draft.autoNext
        step.durationSeconds = max(RoutineStep.minimumDurationSeconds, draft.durationSeconds)
        step.notes = draft.notes
        step.autoShowNotes = draft.autoShowNotes
        try? modelContext.save()
        dismiss()
    }

    /// Three red pulses on whichever of title / icon is missing, and the
    /// cursor in the title if that is one of them.
    private func flashRequiredFields() {
        let title = titleMissing
        let icon = iconMissing
        if title { titleFocused = true }
        withAnimation(.easeInOut(duration: 0.2).repeatCount(5, autoreverses: true)) {
            isFlashingTitle = title
            isFlashingIcon = icon
        }
        Task {
            try? await Task.sleep(for: .seconds(1.05))
            withAnimation(.easeOut(duration: 0.15)) {
                isFlashingTitle = false
                isFlashingIcon = false
            }
        }
    }

    private func deleteStep() {
        modelContext.delete(step)
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Bindings

    private var iconBinding: Binding<String> {
        Binding {
            draft.icon
        } set: { newValue in
            draft.icon = RoutineStep.normalizedIcon(newValue)
        }
    }

    private var minutesBinding: Binding<Int> {
        Binding {
            draft.durationSeconds / 60
        } set: { newMinutes in
            let seconds = draft.durationSeconds % 60
            draft.durationSeconds = max(RoutineStep.minimumDurationSeconds, newMinutes * 60 + seconds)
        }
    }

    private var secondsBinding: Binding<Int> {
        Binding {
            draft.durationSeconds % 60
        } set: { newSeconds in
            let minutes = draft.durationSeconds / 60
            draft.durationSeconds = max(RoutineStep.minimumDurationSeconds, minutes * 60 + newSeconds)
        }
    }
}
