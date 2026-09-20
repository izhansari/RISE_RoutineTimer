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
//  Editing happens *in the list*. Tapping a step opens a minutes / seconds
//  wheel directly beneath it, and a bar rises at the foot of the screen with
//  what the correction does to the run — when it now ends, how long it took —
//  and Cancel / Save. It used to be a sheet (the summary) pushing a page
//  (this one) presenting another sheet (the wheel): three surfaces deep to
//  change one number, and the step you were fixing was hidden behind the
//  thing you were fixing it with.
//
//  The maths is `SessionResult.correcting(stepAt:toSeconds:)`.
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

    /// The step being corrected and where its wheel sits. One at a time.
    @State private var draft: TimeDraft?

    private struct TimeDraft: Equatable {
        var index: Int
        var minutes: Int
        var seconds: Int

        var total: Int { minutes * 60 + seconds }
    }

    /// Ten hours — enough for any step left running overnight.
    private static let maxMinutes = 600
    private static let overColor = Color(hex: 0xE8890A)

    private var session: RoutineSession? { sessions.first { $0.startedAt == startedAt } }

    private var icons: [UUID: String] {
        Dictionary(routineSteps.map { ($0.stepID, $0.icon) }, uniquingKeysWith: { first, _ in first })
    }

    /// The wheel has moved off the recorded time. From here the only ways on
    /// are Cancel and Save: other rows stop answering, the back button goes
    /// and the sheet cannot be swiped away — the same lock a pending reorder
    /// puts on the Run tab, for the same reason. A correction that vanishes
    /// because a neighbouring row was brushed is worse than one extra tap.
    private func isDirty(in result: SessionResult) -> Bool {
        guard let draft, result.steps.indices.contains(draft.index) else { return false }
        return draft.total != result.steps[draft.index].actualSeconds
    }

    var body: some View {
        let result = session?.result
        let dirty = result.map(isDirty(in:)) ?? false

        ScrollViewReader { proxy in
            ScrollView {
                if let result {
                    list(result, dirty: dirty, proxy: proxy)
                } else {
                    Text("This session no longer exists.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let result, let draft, result.steps.indices.contains(draft.index) {
                editBar(result, draft: draft, dirty: dirty)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Correct times")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(dirty)
        .interactiveDismissDisabled(dirty)
    }

    // MARK: - List

    private func list(_ result: SessionResult, dirty: Bool, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(draft.map { result.correcting(stepAt: $0.index, toSeconds: $0.total) } ?? result)
                .padding(.top, 6)
                .padding(.horizontal, 10)

            HStack {
                label("Step")
                Spacer()
                label("Took")
            }
            .padding(.top, 22)
            .padding(.bottom, 4)
            .padding(.horizontal, 10)

            ReceiptRule()
                .padding(.horizontal, 10)

            ForEach(Array(result.steps.enumerated()), id: \.offset) { index, step in
                let isOpen = draft?.index == index

                VStack(spacing: 0) {
                    row(step, isOpen: isOpen)
                        .contentShape(Rectangle())
                        .onTapGesture { tap(index, step: step, dirty: dirty, proxy: proxy) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(step.title), took \(TimeFormatting.spokenDuration(from: step.actualSeconds))")
                        .accessibilityHint(isOpen ? "Closes the time wheel" : "Correct the time")
                        .accessibilityAddTraits(.isButton)

                    if isOpen {
                        wheel
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 10)
                .background {
                    if isOpen {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                    }
                }
                // The wheel is revealed by the box growing, not by sliding
                // over its neighbours.
                .clipped()
                .opacity(dirty && !isOpen ? 0.35 : 1)
                .id(index)

                if !isOpen, draft?.index != index + 1 {
                    ReceiptRule()
                        .padding(.horizontal, 10)
                }
            }

            Text("TAP A STEP TO CORRECT THE TIME IT TOOK. THE RUN'S TOTAL AND END TIME MOVE WITH IT; ITS START STAYS.")
                .font(.system(size: 9, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
                .padding(.top, 14)
                .padding(.horizontal, 10)
        }
        // 12 + the rows' own 10 puts the text at the 22pt margin while the
        // open row's box reaches 10pt past it, as on the Run tab's list.
        .padding(.horizontal, 12)
        .padding(.bottom, 32)
    }

    private func tap(_ index: Int, step: StepResult, dirty: Bool, proxy: ScrollViewProxy) {
        guard !dirty else { return }
        UISelectionFeedbackGenerator().selectionChanged()

        let opening = draft?.index != index
        withAnimation(.snappy(duration: 0.32)) {
            // The wheel opens on what was actually recorded — 111 minutes if
            // that's what the step ran — so the correction starts from the
            // truth. (It once opened at the plan for a runaway, which read as
            // the app having silently changed the number.)
            draft = opening
                ? TimeDraft(
                    index: index,
                    minutes: min(Self.maxMinutes - 1, step.actualSeconds / 60),
                    seconds: step.actualSeconds % 60
                )
                : nil
        }
        guard opening else { return }
        // Once the wheel and the bar have taken their space, bring the row
        // clear of both.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            guard draft?.index == index else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
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
        .contentTransition(.identity)
        .transaction { $0.animation = nil }
    }

    private func row(_ step: StepResult, isOpen: Bool) -> some View {
        // An open row shows where the wheel is, so the list itself reads as
        // it will once saved.
        let shown = isOpen ? (draft?.total ?? step.actualSeconds) : step.actualSeconds
        let changed = shown != step.actualSeconds

        return HStack(spacing: 10) {
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
            Text(TimeFormatting.clockTime(from: shown))
                .font(analogFont(16))
                .monospacedDigit()
                .contentTransition(.identity)
                .foregroundStyle(!changed && isRunaway(step) ? Self.overColor : .primary)
            Image(systemName: isOpen ? "chevron.up" : "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOpen ? .secondary : .tertiary)
                .frame(width: 14)
        }
        .padding(.vertical, 10)
    }

    private var wheel: some View {
        HStack(spacing: 0) {
            Picker("Minutes", selection: draftBinding(\.minutes)) {
                ForEach(0..<Self.maxMinutes, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            Picker("Seconds", selection: draftBinding(\.seconds)) {
                ForEach(0..<60, id: \.self) { Text(String(format: "%02d sec", $0)).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: 132)
        .padding(.bottom, 4)
    }

    private func draftBinding(_ keyPath: WritableKeyPath<TimeDraft, Int>) -> Binding<Int> {
        Binding {
            draft?[keyPath: keyPath] ?? 0
        } set: { value in
            // The numbers around the wheel cut to their new values; only the
            // wheel itself moves.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { draft?[keyPath: keyPath] = value }
        }
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

    // MARK: - Edit bar

    /// What the correction does, and the two ways out. Pinned to the foot of
    /// the screen so it stays put while the list scrolls under it.
    private func editBar(_ result: SessionResult, draft: TimeDraft, dirty: Bool) -> some View {
        let step = result.steps[draft.index]
        let preview = result.correcting(stepAt: draft.index, toSeconds: draft.total)
        // Marked as moved only when the *printed* value differs: three
        // seconds on a step changes the run's end without changing "7:19AM".
        let ends = TimeFormatting.shortClockTime(from: preview.endedAt).uppercased()
        let took = TimeFormatting.clockTime(from: preview.activeSeconds)

        return VStack(spacing: 12) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cell("Recorded", TimeFormatting.clockTime(from: step.actualSeconds))
                    hairline(vertical: true)
                    cell("Planned", TimeFormatting.clockTime(from: step.plannedSeconds))
                }
                .fixedSize(horizontal: false, vertical: true)
                hairline(vertical: false)
                HStack(spacing: 0) {
                    cell("Run ends", ends,
                         changed: ends != TimeFormatting.shortClockTime(from: result.endedAt).uppercased())
                    hairline(vertical: true)
                    cell("Run took", took,
                         changed: took != TimeFormatting.clockTime(from: result.activeSeconds))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))

            // Giving a skipped step a time says it happened; say so before
            // Save does it.
            if step.wasSkipped, dirty, draft.total > 0 {
                Text("SAVING COUNTS THIS STEP AS DONE, NOT SKIPPED")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            HStack(spacing: 10) {
                ReceiptButton(title: "Cancel") {
                    withAnimation(.snappy(duration: 0.32)) { self.draft = nil }
                }
                // Outlined and faint until the wheel has moved. A filled button
                // at 40% was white type on pale grey — unreadable, and it
                // looked broken rather than waiting.
                ReceiptButton(title: "Save", fill: dirty ? .primary : nil) {
                    save(stepAt: draft.index, seconds: draft.total)
                }
                .disabled(!dirty)
                .opacity(dirty ? 1 : 0.35)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .background {
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 12, y: -3)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
        }
    }

    private func cell(_ title: String, _ value: String, changed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            Text(value)
                .font(analogFont(16))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.identity)
            // The two numbers the correction moves are underlined once it has.
            Rectangle()
                .fill(changed ? Color.primary : Color.clear)
                .frame(width: 18, height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func hairline(vertical: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }

    /// Writes the corrected run back. The start stays; the step's time, the
    /// run's active time and its end all move together.
    private func save(stepAt index: Int, seconds: Int) {
        guard let session else { return }
        session.apply(session.result.correcting(stepAt: index, toSeconds: seconds))
        try? modelContext.save()
        withAnimation(.snappy(duration: 0.32)) { draft = nil }
    }
}
