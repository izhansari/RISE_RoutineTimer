//
//  RunSheetView.swift
//  RISE_RoutineTimer
//
//  Everything about the current run that is not worth a permanent place on
//  the timer screen, behind the chevron on the bottom bar: the step's note,
//  the run's numbers, the display toggles, and the way out.
//
//  The numbers here — pace, projected end, spare time, step n of m — were
//  once on the timer screen itself and got cut for density. They were never
//  bad data, just badly placed. One tap away is the right distance.
//

import SwiftData
import SwiftUI

struct RunSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let engine: RoutineEngine
    let schedule: TargetSchedule
    /// Called after this sheet has dismissed itself, so the caller can present
    /// the notes sheet in its place. `true` asks for it to open straight into
    /// editing — the "Add" case, where there is nothing to read yet.
    let onShowNotes: (_ editing: Bool) -> Void
    /// Likewise for the end-routine confirmation.
    let onEnd: () -> Void

    @AppStorage(ActiveScreenSettings.showStepTimesKey) private var showStepTimes = true
    @AppStorage(ActiveScreenSettings.showNextStepKey) private var showNextStep = true

    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]

    private var stats: RoutineStats { RoutineStats(sessions: sessions.map(\.result)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                section("Note") { noteRow }
                section("This run") { runStats }
                section("This step") { stepStats }
                section("Display") {
                    ReceiptToggle(title: "Step times", isOn: $showStepTimes)
                        .padding(.vertical, 9)
                    ReceiptRule()
                    ReceiptToggle(title: "Next step", isOn: $showNextStep)
                        .padding(.vertical, 9)
                }

                ReceiptButton(title: "End routine", fill: Color(hex: 0xDB2118)) {
                    dismiss()
                    onEnd()
                }
                .padding(.top, 2)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 22)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("STEP \(engine.currentIndex + 1) OF \(engine.steps.count)")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            ReceiptSheetTitle(title: engine.currentStep?.title ?? "Routine")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    /// A titled group. The rows sit inside a hairline box, so where one
    /// section ends and the next begins is drawn rather than implied by
    /// whitespace — the earlier version spaced everything evenly and it was
    /// not obvious which numbers belonged together.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ReceiptSection(title, content: content)
    }

    private var noteRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let note = engine.currentStep?.notes, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                } else {
                    Text("No note for this step.")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ReceiptBarButton(title: engine.currentStep?.hasNotes == true ? "Open" : "Add") {
                let hasNote = engine.currentStep?.hasNotes == true
                dismiss()
                onShowNotes(!hasNote)
            }
        }
        .padding(.vertical, 10)
    }

    private var runStats: some View {
        VStack(spacing: 0) {
            if let start = engine.routineStartDate {
                statRow("Time", TimeFormatting.clockRange(from: start, to: engine.projectedEndDate))
                ReceiptRule()
            }
            statRow("Elapsed", TimeFormatting.clockTime(from: engine.activeElapsedSeconds))
            ReceiptRule()
            statRow("Pace", RoutinePace.label(deltaSeconds: engine.scheduleDeltaSeconds))
            if let spare = schedule.spareSeconds(projectedEnd: engine.projectedEndDate) {
                ReceiptRule()
                statRow("Target", TargetSchedule.spareText(spare))
            }
        }
    }

    /// How this step usually goes, against how long it was given.
    private var stepStats: some View {
        let planned = engine.currentStep?.durationSeconds ?? 0
        let average = engine.currentStep.flatMap { stats.averageActual(forStepID: $0.id) }

        return VStack(spacing: 0) {
            statRow("Planned", TimeFormatting.clockTime(from: planned))
            ReceiptRule()
            if let average {
                statRow("Average", TimeFormatting.clockTime(from: average.averageSeconds),
                        detail: "\(average.sampleCount) runs")
                ReceiptRule()
                let delta = average.averageSeconds - planned
                statRow("Vs plan", delta == 0 ? "ON PLAN"
                        : "\(delta < 0 ? "−" : "+")\(TimeFormatting.clockTime(from: abs(delta)))")
            } else {
                statRow("Average", "—", detail: "after 2 runs")
            }
        }
    }

    private func statRow(_ label: String, _ value: String, detail: String? = nil) -> some View {
        ReceiptStatRow(label, value, detail: detail)
    }
}
