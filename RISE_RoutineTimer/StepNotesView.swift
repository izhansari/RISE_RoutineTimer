//
//  StepNotesView.swift
//  RISE_RoutineTimer
//
//  The notes sheet: read the note during a run, and edit it deliberately.
//
//  Reading and editing are separate modes on purpose. The whole sheet used to
//  be a live `TextEditor` bound straight to the saved step, so a stray tap put
//  you in the keyboard and every keystroke was already saved. Now the text is
//  plain until you ask to edit, edits go to a local draft, and nothing reaches
//  the step until you press Save.
//
//  The chrome also follows the detent. At the medium height this is a glance
//  surface — note text and nothing else. Editing is only offered once the
//  sheet is fully open, where there is room to type.
//
//  Body text is set in the system font, not the receipt face: the dot-matrix
//  type is for labels and digits and is hard to read at paragraph length.
//

import SwiftData
import SwiftUI

struct StepNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// The saved step. Only written on an explicit save.
    @Bindable var step: RoutineStep
    /// Pushes the saved text into the engine's frozen copy of the run.
    let onCommit: (String) -> Void

    @State private var detent: PresentationDetent
    @State private var isEditing: Bool
    @State private var draft: String
    @State private var confirmingDiscard = false
    @FocusState private var typing: Bool

    /// Open fully with the editor and keyboard already up — for "Add" from
    /// the run sheet, where making the user drag the sheet open and then find
    /// Edit was three steps too many.
    private let startEditing: Bool

    init(step: RoutineStep, startEditing: Bool = false, onCommit: @escaping (String) -> Void) {
        _step = Bindable(step)
        self.onCommit = onCommit
        self.startEditing = startEditing
        _detent = State(initialValue: startEditing ? .large : .medium)
        _isEditing = State(initialValue: startEditing)
        _draft = State(initialValue: step.notes)
    }

    private var isFullyOpen: Bool { detent == .large }
    private var hasUnsavedChanges: Bool { draft != step.notes }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, isFullyOpen ? 16 : 12)

            if isFullyOpen {
                ReceiptSheetTitle(title: step.title)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
            }

            if isEditing {
                editor
            } else {
                reader
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Opaque at every height — the translucent default let the timer's
        // fill colour bleed through the note and made it hard to read.
        .presentationBackground(Color(.systemBackground))
        // While editing there is uncommitted text, so the sheet cannot be
        // swiped away by accident: Save or Cancel are the only ways out.
        .interactiveDismissDisabled(isEditing)
        .receiptDialog(
            isPresented: $confirmingDiscard,
            title: "Discard changes?",
            message: "Your edits to this note won't be saved.",
            confirmTitle: "Discard",
            cancelTitle: "Keep editing",
            onConfirm: stopEditing
        )
        .onChange(of: detent) { _, new in
            // Collapsing the sheet leaves the editor; the draft is kept so
            // re-opening resumes where it left off.
            if new != .large { typing = false }
        }
        .onChange(of: step.autoShowNotes) { _, _ in
            try? modelContext.save()
        }
        // Belt and braces for `startEditing`: a `@State(initialValue:)` set in
        // `init` is not honoured when SwiftUI reuses the sheet's state storage
        // from an earlier presentation, and "Add" then opened a half-height,
        // read-only sheet. Applying it on appear works either way.
        .onAppear {
            guard startEditing, !isEditing else { return }
            draft = step.notes
            isEditing = true
            detent = .large
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        HStack {
            if isEditing {
                ReceiptBarButton(title: "Cancel") {
                    if hasUnsavedChanges { confirmingDiscard = true } else { stopEditing() }
                }
                Spacer()
                ReceiptBarButton(title: "Save", prominent: true, action: save)
            } else {
                // Editing is only offered at full height, where there is room
                // for the keyboard and the whole note at once.
                if isFullyOpen {
                    ReceiptBarButton(title: "Edit") {
                        draft = step.notes
                        isEditing = true
                    }
                } else {
                    Color.clear.frame(width: 1, height: 30)
                }
                Spacer()
                ReceiptTogglePill(title: "Auto-open", isOn: $step.autoShowNotes)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isEditing)
        .animation(.easeOut(duration: 0.15), value: isFullyOpen)
    }

    // MARK: - Reading

    private var reader: some View {
        ScrollView {
            Group {
                if step.notes.isEmpty {
                    VStack(spacing: 8) {
                        Text("NO NOTE")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(.tertiary)
                        Text(isFullyOpen ? "Tap Edit to write one." : "Open the sheet fully to write one.")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                } else {
                    Text(step.notes)
                        .font(.system(size: 17))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Editing

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text("Write a note for this step…")
                    .font(.system(size: 17))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 25)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $draft)
                .font(.system(size: 17))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 20)
                .focused($typing)
                // Notes hold transliterated Arabic and proper nouns that
                // autocorrect mangles into nonsense — it turned
                // "Alhamdu lillahil-lathee ahyana" into "Albany's ... Shayna".
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
        }
        .onAppear { typing = true }
    }

    // MARK: - Actions

    private func save() {
        step.notes = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        onCommit(step.notes)
        stopEditing()
    }

    private func stopEditing() {
        typing = false
        isEditing = false
        draft = step.notes
    }
}

/// Fallback for a step that has been deleted from the routine mid-run: the
/// frozen copy still has text worth showing, but there is nothing to edit.
struct FrozenNotesView: View {
    let title: String
    let notes: String

    @State private var detent: PresentationDetent = .medium

    var body: some View {
        VStack(spacing: 0) {
            if detent == .large {
                ReceiptSheetTitle(title: title)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
            }

            ScrollView {
                Text(notes)
                    .font(.system(size: 17))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, detent == .large ? 0 : 24)
                    .padding(.bottom, 28)
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }
}
