//
//  RoutineTimerView.swift
//  RISE_RoutineTimer
//
//  The "Run" tab. Idle screen (ready / paused / complete) and the active
//  timer screen. All timing comes from `RoutineEngine`; this file only draws.
//

import SwiftData
import SwiftUI
import UIKit

struct RoutineTimerView: View {
    @Environment(RoutineEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @AppStorage(RoutineAlertCoordinator.soundsKey) private var soundsEnabled = true
    @AppStorage(RoutineAlertCoordinator.voiceKey) private var voiceEnabled = true
    @AppStorage(TargetSchedule.targetKey) private var targetMinutes = TargetSchedule.none
    @AppStorage(FillTheme.storageKey) private var fillThemeRaw = FillTheme.default.rawValue

    let steps: [RoutineStep]

    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]

    /// The notes sheet is presented by *item*, with "open straight into
    /// editing" carried inside it. It was a Bool `isPresented` plus a separate
    /// editing flag, and the flag kept arriving as false: the sheet's own
    /// `onDismiss` reset it during the hand-off from the run sheet. An item is
    /// captured at presentation and nothing can zero it out underneath.
    @State private var notesRequest: NotesRequest?
    /// A step being edited from the idle list. Presented as a sheet so the
    /// Run tab's own navigation stays put.
    @State private var editingStep: RoutineStep?
    /// The step index whose notes were last auto-presented, so switching tabs
    /// or coming back from the background doesn't re-open the same sheet.
    @State private var lastAutoNotesIndex: Int?
    @State private var summaryResult: SessionResult?
    @State private var editingRoutine = false

    var body: some View {
        NavigationStack {
            Group {
                if steps.isEmpty && engine.run == nil {
                    ContentUnavailableView(
                        "No Routine Steps",
                        systemImage: "list.bullet",
                        description: Text("Tap the pencil to add your first step.")
                    )
                } else if engine.hasActiveRun {
                    // Paused included: a pause dims the timer in place rather
                    // than dropping back here, which read as "routine over".
                    activeRoutineScreen
                } else {
                    idleScreen
                }
            }
            .navigationTitle("Morning Routine")
            .toolbar(engine.hasActiveRun ? .hidden : .visible, for: .navigationBar)
            .toolbar(engine.hasActiveRun ? .hidden : .visible, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { editingRoutine = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Edit routine")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    alertsMenu
                }
            }
            .sheet(isPresented: $editingRoutine) {
                RoutineListView(steps: steps)
            }
        }
        .onChange(of: engine.isComplete) { wasComplete, isComplete in
            if isComplete, !wasComplete, let run = engine.run {
                summaryResult = SessionResult(
                    startedAt: run.startedAt,
                    endedAt: run.endedAt ?? engine.now,
                    plannedSeconds: run.plannedSeconds,
                    activeSeconds: engine.activeElapsedSeconds,
                    pausedSeconds: engine.pausedSeconds,
                    completed: true,
                    steps: run.results
                )
            }
        }
        .sheet(item: $summaryResult) { result in
            SessionSummaryView(result: result)
        }
        .sheet(item: $editingStep) { step in
            NavigationStack {
                StepEditorView(step: step)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { editingStep = nil }
                        }
                    }
            }
        }
        .onChange(of: engine.currentIndex, initial: true) { _, _ in
            autoShowNotesIfWanted()
        }
        .onChange(of: engine.hasActiveRun) { _, active in
            // Starting a run does not change `currentIndex` — it is already 0 —
            // so the first step's notes have to be triggered from here.
            if active {
                autoShowNotesIfWanted()
            } else {
                lastAutoNotesIndex = nil
            }
        }
    }

    private var alertsMenu: some View {
        Menu {
            Toggle(isOn: $soundsEnabled) { Label("Chimes", systemImage: "bell") }
            Toggle(isOn: $voiceEnabled) { Label("Voice", systemImage: "waveform") }
        } label: {
            Image(systemName: soundsEnabled || voiceEnabled ? "speaker.wave.2" : "speaker.slash")
        }
        .accessibilityLabel("Alert settings")
    }

    // MARK: - Idle Screen

    /// While a run exists, the list mirrors the run's frozen steps so edits
    /// made mid-routine don't shuffle the checkmarks.
    private var displayedSteps: [RunStep] {
        engine.run == nil ? steps.map(RunStep.init) : engine.steps
    }

    private var idleScreen: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(idleStatusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2.5)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(idleHeadlineTime)
                            .font(analogFont(30))
                    }
                    .padding(.top, 20)
                    .padding(.bottom, (idleSummaryLine ?? readyContextLine) == nil ? 20 : 6)

                    if let line = idleSummaryLine ?? readyContextLine {
                        Text(line)
                            .font(analogFont(16))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 16)
                    }

                    Divider().padding(.bottom, 12)

                    // Tapping a step edits it in place, and the + on each
                    // connector inserts a new one exactly there — going through
                    // the pencil was a detour nobody remembered to take.
                    // Only while no run exists: a finished run shows the frozen
                    // order, which may differ from the saved one.
                    let rows = displayedSteps
                    let editable = engine.run == nil
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, step in
                        Button {
                            guard editable, let live = liveStep(for: step) else { return }
                            editingStep = live
                        } label: {
                            IdleStepRow(
                                step: step,
                                index: index,
                                currentIndex: engine.currentIndex,
                                isRoutineComplete: engine.isComplete,
                                isRoutineActive: engine.run != nil
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!editable)

                        if index < rows.count - 1 {
                            InsertConnector(enabled: editable) { insertStep(after: index) }
                        }
                    }

                    if editable {
                        Button { insertStep(after: rows.count - 1) } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1.5))
                                Text("ADD STEP")
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(1.8)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 24)
            }

            VStack(spacing: 10) {
                Divider()

                Button(action: primaryAction) {
                    HStack(spacing: 10) {
                        Image(systemName: primaryButtonIcon)
                            .font(.system(size: 17))
                        Text(primaryButtonTitle.uppercased())
                            .font(analogFont(22))
                            .tracking(2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.primary)
                    .foregroundStyle(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            }
            .padding(.bottom, 10)
        }
    }

    /// The saved step behind a displayed one, by stable id.
    private func liveStep(for step: RunStep) -> RoutineStep? {
        steps.first { $0.stepID == step.id }
    }

    /// Inserts a fresh step after `index` in the saved order and opens it.
    private func insertStep(after index: Int) {
        var ordered = steps
        let step = RoutineStep(title: "New Step", durationSeconds: 5 * 60, autoNext: true, notes: "", sortOrder: 0)
        modelContext.insert(step)
        ordered.insert(step, at: min(index + 1, ordered.count))
        for (position, existing) in ordered.enumerated() {
            existing.sortOrder = position
        }
        try? modelContext.save()
        editingStep = step
    }

    private var idleStatusLabel: String {
        if engine.isComplete { return "COMPLETE" }
        if engine.isPaused { return "PAUSED" }
        return "READY"
    }

    private var idleHeadlineTime: String {
        if engine.isComplete {
            return TimeFormatting.clockTime(from: engine.activeElapsedSeconds)
        }
        let planned = engine.run == nil
            ? steps.reduce(0) { $0 + $1.durationSeconds }
            : engine.plannedTotalSeconds
        return TimeFormatting.durationText(from: planned)
    }

    private var idleSummaryLine: String? {
        guard let start = engine.routineStartDate else { return nil }
        let started = "Started \(TimeFormatting.shortClockTime(from: start))"
        if engine.isComplete {
            let delta = TimeFormatting.scheduleDeltaText(from: engine.scheduleDeltaSeconds)
            return "\(started) · \(delta.lowercased())"
        }
        if engine.isPaused {
            return "\(started) · step \(engine.currentIndex + 1) of \(engine.steps.count)"
        }
        return nil
    }

    private var schedule: TargetSchedule { TargetSchedule(targetMinutesAfterMidnight: targetMinutes) }

    private var fillTheme: FillTheme { FillTheme(rawValue: fillThemeRaw) ?? .default }

    /// Start-by guidance plus yesterday's result, shown while READY.
    private var readyContextLine: String? {
        guard engine.run == nil else { return nil }
        var parts: [String] = []
        let planned = steps.reduce(0) { $0 + $1.durationSeconds }
        if let startBy = schedule.startByDate(on: engine.now, plannedSeconds: planned),
           let target = schedule.targetDate(on: engine.now) {
            if engine.now <= startBy {
                parts.append("Start by \(TimeFormatting.shortClockTime(from: startBy)) for \(TimeFormatting.shortClockTime(from: target))")
            } else if engine.now < target {
                parts.append("Past start time for \(TimeFormatting.shortClockTime(from: target))")
            }
        }
        let stats = RoutineStats(sessions: sessions.map(\.result))
        guard let latest = stats.latest else { return parts.isEmpty ? nil : parts.joined(separator: " · ") }
        parts.append("Last \(TimeFormatting.clockTime(from: latest.activeSeconds))")
        if !schedule.isSet, let average = stats.averageStartSecondsSinceMidnight, stats.count >= 2 {
            let clock = Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(average))
            parts.append("usually start \(TimeFormatting.shortClockTime(from: clock))")
        }
        let streak = stats.currentStreak()
        if streak >= 2 { parts.append("\(streak) day streak") }
        return parts.joined(separator: " · ")
    }

    private var primaryButtonTitle: String {
        if engine.isComplete { return "Start Over" }
        if engine.isPaused { return "Resume" }
        return "Start"
    }

    private var primaryButtonIcon: String {
        if engine.isComplete { return "arrow.counterclockwise" }
        return "play.fill"
    }

    private func primaryAction() {
        if engine.isPaused {
            engine.resume()
        } else {
            if engine.isComplete { engine.reset() }
            engine.start(steps: steps.map(RunStep.init))
        }
    }

    // MARK: - Active Screen

    private var activeRoutineScreen: some View {
        ActiveRoutineView(
            engine: engine,
            schedule: schedule,
            theme: fillTheme,
            onShowNotes: { editing in
                notesRequest = NotesRequest(editing: editing)
            },
            onEnd: { engine.abandon() }
        )
        .sheet(item: $notesRequest) { request in
            notesSheet(editing: request.editing)
        }
    }

    /// Edits go to the saved step, then get pushed into the run's frozen copy
    /// so the screen reflects them straight away.
    @ViewBuilder
    private func notesSheet(editing: Bool) -> some View {
        if let step = currentModelStep {
            StepNotesView(step: step, startEditing: editing) { notes in
                engine.updateNotes(notes, forStepID: step.stepID)
            }
        } else {
            FrozenNotesView(
                title: engine.currentStep?.title ?? "Notes",
                notes: engine.currentStep?.notes ?? ""
            )
        }
    }

    /// The saved step behind the current frozen one. Nil if it was deleted
    /// from the routine while the run was in progress.
    private var currentModelStep: RoutineStep? {
        guard let id = engine.currentStep?.id else { return nil }
        return steps.first { $0.stepID == id }
    }

    /// Opens the notes sheet as a step begins, when that step asks for it.
    private func autoShowNotesIfWanted() {
        guard engine.isRunning else { return }
        let index = engine.currentIndex
        guard lastAutoNotesIndex != index else { return }
        lastAutoNotesIndex = index
        guard let step = engine.currentStep, step.hasNotes, step.autoShowNotes else { return }
        notesRequest = NotesRequest(editing: false)
    }

}

// MARK: - Idle Step Row

private struct IdleStepRow: View {
    let step: RunStep
    let index: Int
    let currentIndex: Int
    let isRoutineComplete: Bool
    let isRoutineActive: Bool

    private var isDone: Bool { isRoutineComplete || (isRoutineActive && index < currentIndex) }
    private var isCurrent: Bool { !isRoutineComplete && index == currentIndex }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(isDone || isCurrent ? Color.primary : Color.clear)
                Circle()
                    .strokeBorder(
                        Color.primary.opacity(isDone || isCurrent ? 0 : 0.3),
                        lineWidth: 1.5
                    )

                if !step.icon.isEmpty, !isDone {
                    Text(step.icon)
                        .font(.system(size: isCurrent ? 14 : 13))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(.systemBackground)))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(isCurrent ? 1 : 0.3), lineWidth: 1.5))
                } else if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(.systemBackground))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color(.systemBackground) : .secondary)
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(analogFont(isCurrent ? 20 : 18))
                    .foregroundStyle(isDone ? .secondary : .primary)

                HStack(spacing: 8) {
                    Text(TimeFormatting.durationText(from: step.durationSeconds))
                        .font(analogFont(13))
                        .foregroundStyle(.secondary)

                    if !step.autoNext {
                        Text("MANUAL")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }

                if isCurrent, step.hasNotes {
                    Text(step.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .lineLimit(3)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .opacity(isDone ? 0.5 : 1)
    }
}

// MARK: - Insert Connector

/// The thin line between two idle rows, with a + on it. Tapping it inserts a
/// step at exactly that point in the sequence.
private struct InsertConnector: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 1.5, height: 20)
                    if enabled {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(Color(.systemBackground)))
                            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
                    }
                }
                .frame(width: 24)   // centred under the step circle
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Insert a step here")
    }
}

/// One request to show the notes sheet. A fresh `id` per request, so asking
/// again while it is up is a new presentation rather than a no-op.
private struct NotesRequest: Identifiable {
    let id = UUID()
    let editing: Bool
}
