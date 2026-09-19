//
//  SessionEditView.swift
//  RISE_RoutineTimer
//
//  Correcting a past run, on its own screen — pushed from EDIT on the session
//  summary. Every step gets its own row here, auto ones included: the summary
//  folds a run of auto steps into one line, which is right for reading and
//  wrong for fixing, because a single step inside the group couldn't be
//  reached.
//
//  Tapping a step opens `StepTimeEditor`. The maths is
//  `SessionResult.correcting(stepAt:toSeconds:)`.
//

import SwiftData
import SwiftUI
import UIKit

struct SessionEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]
    @Query private var routineSteps: [RoutineStep]

    /// The session's identity; a correction never changes it.
    let startedAt: Date

    @State private var editTarget: StepEditTarget?

    private var session: RoutineSession? { sessions.first { $0.startedAt == startedAt } }

    private var icons: [UUID: String] {
        Dictionary(routineSteps.map { ($0.stepID, $0.icon) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollView {
            if let result = session?.result {
                VStack(alignment: .leading, spacing: 0) {
                    header(result)
                        .padding(.top, 6)

                    HStack {
                        label("Step")
                        Spacer()
                        label("Took")
                    }
                    .padding(.top, 22)
                    .padding(.bottom, 4)

                    ReceiptRule()

                    ForEach(Array(result.steps.enumerated()), id: \.offset) { index, step in
                        row(step)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UISelectionFeedbackGenerator().selectionChanged()
                                editTarget = StepEditTarget(index: index)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(step.title), took \(TimeFormatting.spokenDuration(from: step.actualSeconds))")
                            .accessibilityHint("Correct the time")
                            .accessibilityAddTraits(.isButton)
                        ReceiptRule()
                    }

                    Text("TAP A STEP TO CORRECT THE TIME IT TOOK. THE RUN'S TOTAL AND END TIME MOVE WITH IT; ITS START STAYS.")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1.3)
                        .foregroundStyle(.tertiary)
                        .lineSpacing(2)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
                .sheet(item: $editTarget) { target in
                    StepTimeEditor(session: result, index: target.index) { seconds in
                        save(stepAt: target.index, seconds: seconds)
                    }
                }
            } else {
                Text("This session no longer exists.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Correct times")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func header(_ result: SessionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TimeFormatting.clockRange(from: result.startedAt, to: result.endedAt))
                .font(analogFont(26))
                .tracking(1)
                .monospacedDigit()
            Text("TOOK \(TimeFormatting.clockTime(from: result.activeSeconds)) · PLANNED \(TimeFormatting.clockTime(from: result.plannedSeconds))")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ step: StepResult) -> some View {
        HStack(spacing: 10) {
            Text(icons[step.stepID] ?? "")
                .font(.system(size: 15))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title.uppercased())
                    .font(analogFont(13))
                    .tracking(0.4)
                    .lineLimit(1)
                Text("PLAN \(TimeFormatting.clockTime(from: step.plannedSeconds))\(step.autoAdvanced ? " · AUTO" : "")\(step.wasSkipped ? " · SKIPPED" : "")")
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Text(TimeFormatting.clockTime(from: step.actualSeconds))
                .font(analogFont(16))
                .monospacedDigit()
                .foregroundStyle(isRunaway(step) ? Color(hex: 0xE8890A) : .primary)
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    /// Worth drawing the eye to: well past any plausible time for the step.
    private func isRunaway(_ step: StepResult) -> Bool {
        step.actualSeconds > 3 * max(step.plannedSeconds, 60)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(.secondary)
    }

    /// Writes the corrected run back. The start stays; the step's time, the
    /// run's active time and its end all move together.
    private func save(stepAt index: Int, seconds: Int) {
        guard let session else { return }
        session.apply(session.result.correcting(stepAt: index, toSeconds: seconds))
        try? modelContext.save()
    }
}

// MARK: - Correcting a step's time

struct StepEditTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

/// A small wheel editor for one step's recorded time. It previews what the
/// correction does to the whole run — when it now ends, how long it took —
/// so the fix can be checked against the clock before it is saved.
struct StepTimeEditor: View {
    @Environment(\.dismiss) private var dismiss

    let session: SessionResult
    let index: Int
    let onSave: (Int) -> Void

    @State private var minutes: Int
    @State private var seconds: Int

    /// Ten hours — enough for any step left running overnight.
    private static let maxMinutes = 600

    init(session: SessionResult, index: Int, onSave: @escaping (Int) -> Void) {
        self.session = session
        self.index = index
        self.onSave = onSave
        // The wheel opens on what was actually recorded — 111 minutes if
        // that's what the step ran — so the correction starts from the
        // truth. (It once opened at the plan for a runaway, which read as the
        // app having silently changed the number.)
        let actual = session.steps.indices.contains(index) ? session.steps[index].actualSeconds : 0
        _minutes = State(initialValue: min(Self.maxMinutes - 1, actual / 60))
        _seconds = State(initialValue: actual % 60)
    }

    private var step: StepResult? { session.steps.indices.contains(index) ? session.steps[index] : nil }
    private var newSeconds: Int { minutes * 60 + seconds }
    private var preview: SessionResult { session.correcting(stepAt: index, toSeconds: newSeconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CORRECT TIME")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
            Text((step?.title ?? "").uppercased())
                .font(analogFont(20))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 6)

            HStack(spacing: 0) {
                Picker("Minutes", selection: $minutes) {
                    ForEach(0..<Self.maxMinutes, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
                Picker("Seconds", selection: $seconds) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d sec", $0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 140)
            .padding(.top, 6)

            VStack(spacing: 0) {
                row("Recorded", TimeFormatting.clockTime(from: step?.actualSeconds ?? 0))
                ReceiptRule()
                row("Planned", TimeFormatting.clockTime(from: step?.plannedSeconds ?? 0))
                ReceiptRule()
                row("Run ends", TimeFormatting.clockRange(from: preview.startedAt, to: preview.endedAt))
                ReceiptRule()
                row("Run took", TimeFormatting.clockTime(from: preview.activeSeconds))
            }
            .padding(.horizontal, 12)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
            .padding(.top, 10)

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                ReceiptButton(title: "Cancel") { dismiss() }
                ReceiptButton(title: "Save", fill: .primary) {
                    onSave(newSeconds)
                    dismiss()
                }
                .disabled(newSeconds == step?.actualSeconds)
                .opacity(newSeconds == step?.actualSeconds ? 0.4 : 1)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 22)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(analogFont(16))
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }
}
