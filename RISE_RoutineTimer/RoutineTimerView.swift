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
    @State private var editingStep: StepEditRequest?
    /// The step index whose notes were last auto-presented, so switching tabs
    /// or coming back from the background doesn't re-open the same sheet.
    @State private var lastAutoNotesIndex: Int?
    @State private var summaryResult: SessionResult?
    /// The idle row whose actions are showing. Tapping a step selects it —
    /// its two insert points and its edit / stats buttons appear — and a
    /// second tap puts them away. Cleared when a run starts.
    @State private var selectedStepID: UUID?
    /// A step whose stats sheet is up (the arrow on a selected row).
    @State private var statsStep: RoutineStep?
    /// A drag-reorder in progress: the step ids in their dragged order. The
    /// list shows this order, but nothing is written until Save — a Cancel /
    /// Save pair replaces the Start button while it is set, so an accidental
    /// drag cannot quietly rearrange the morning.
    @State private var pendingOrder: [UUID]?
    /// A swiped-away step waiting for the confirm dialog. The dialog's
    /// visibility is a *separate* Bool: `receiptDialog` clears its binding
    /// before it runs the confirm action, so driving the dialog off this
    /// optional nilled the step just before the delete read it.
    @State private var stepPendingDelete: RunStep?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if steps.isEmpty && engine.run == nil {
                    ContentUnavailableView {
                        Label("No Routine Steps", systemImage: "list.bullet")
                    } description: {
                        Text("Add a step to build your routine.")
                    } actions: {
                        Button("Add Step") { insertStep(after: -1) }
                    }
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
            // While a reorder is pending the tab bar goes too: the only ways
            // out of the proposal are Cancel and Save Order.
            .toolbar(engine.hasActiveRun || hasPendingOrder ? .hidden : .visible, for: .tabBar)
            .sheet(item: $statsStep) { step in
                StepStatsSheet(step: step, stats: RoutineStats(sessions: sessions.map(\.result)))
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
        .sheet(item: $editingStep) { request in
            // The editor carries its own Cancel / Save; nothing is written
            // to the step until Save.
            NavigationStack {
                StepEditorView(request: request)
            }
        }
        .onChange(of: engine.currentIndex, initial: true) { _, _ in
            autoShowNotesIfWanted()
        }
        .onChange(of: engine.hasActiveRun) { _, active in
            // Starting a run does not change `currentIndex` — it is already 0 —
            // so the first step's notes have to be triggered from here.
            if active {
                selectedStepID = nil
                autoShowNotesIfWanted()
            } else {
                lastAutoNotesIndex = nil
            }
        }
    }

    // MARK: - Idle Screen

    /// While a run exists, the list mirrors the run's frozen steps so edits
    /// made mid-routine don't shuffle the checkmarks.
    private var displayedSteps: [RunStep] {
        engine.run == nil ? orderedSteps.map(RunStep.init) : engine.steps
    }

    /// The saved steps in the pending drag order, or the saved order.
    private var orderedSteps: [RoutineStep] {
        guard let pendingOrder else { return steps }
        let byID = Dictionary(steps.map { ($0.stepID, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered = pendingOrder.compactMap { byID[$0] }
        // Anything inserted since the drag began keeps its saved position.
        for step in steps where !pendingOrder.contains(step.stepID) {
            ordered.append(step)
        }
        return ordered
    }

    private var hasPendingOrder: Bool {
        guard let pendingOrder else { return false }
        return pendingOrder != steps.map(\.stepID)
    }

    private var idleScreen: some View {
        let rows = displayedSteps
        // A pending reorder locks everything but the drag itself: no
        // selection (so no edit, stats or insert), no swipe-delete, no Add.
        let editable = engine.run == nil && !hasPendingOrder
        let selected = editable ? selectedStepID : nil

        return VStack(spacing: 0) {
            // A List rather than a ScrollView so rows can be swiped away and
            // dragged into a new order. Each row owns the connector beneath
            // it, so a drag moves the step and its line together.
            List {
                idleHeader
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                // Tapping a step *selects* it: the row highlights, a +
                // appears on the connector above and below it, and edit /
                // stats buttons sit at its right. Nothing else on the list
                // carries chrome, so a resting routine is just the steps.
                // Only while no run exists: a finished run shows the frozen
                // order, which may differ from the saved one.
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, step in
                    let isSelected = selected == step.id

                    VStack(alignment: .leading, spacing: 0) {
                        if index == 0, isSelected {
                            InsertConnector(enabled: true) { insertStep(after: -1) }
                        }

                        IdleStepRow(
                            step: step,
                            index: index,
                            currentIndex: engine.currentIndex,
                            isRoutineComplete: engine.isComplete,
                            isRoutineActive: engine.run != nil,
                            isSelected: isSelected,
                            onEdit: {
                                guard let live = liveStep(for: step) else { return }
                                editingStep = StepEditRequest(step: live)
                            },
                            onStats: {
                                guard let live = liveStep(for: step) else { return }
                                statsStep = live
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard editable else { return }
                            selectedStepID = isSelected ? nil : step.id
                        }

                        if index < rows.count - 1 {
                            let nextSelected = selected == rows[index + 1].id
                            InsertConnector(enabled: isSelected || nextSelected) { insertStep(after: index) }
                        } else if isSelected {
                            InsertConnector(enabled: true) { insertStep(after: index) }
                        }
                    }
                    // 14 + the row's own 10 puts the text at the 24pt margin
                    // while the selection highlight reaches 10pt past it.
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if editable {
                            Button(role: .destructive) {
                                stepPendingDelete = step
                                isConfirmingDelete = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .moveDisabled(engine.run != nil)
                }
                .onMove(perform: moveSteps)

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
                        .padding(.bottom, 24)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            VStack(spacing: 10) {
                Divider()

                if hasPendingOrder {
                    orderButtons
                } else {
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
            }
            .padding(.bottom, 10)
        }
        .receiptDialog(
            isPresented: $isConfirmingDelete,
            title: "Delete \(stepPendingDelete?.title ?? "this step")?",
            message: "It leaves the routine. Past runs keep their record of it.",
            confirmTitle: "Delete Step"
        ) {
            if let step = stepPendingDelete { deleteStep(step) }
            stepPendingDelete = nil
        }
    }

    private var idleHeader: some View {
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
        }
    }

    /// Replaces Start while a drag-reorder is pending. The order on screen
    /// is a proposal until Save.
    private var orderButtons: some View {
        HStack(spacing: 12) {
            Button(action: cancelPendingOrder) {
                Text("CANCEL")
                    .font(analogFont(20))
                    .tracking(2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .foregroundStyle(Color.primary)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            Button(action: savePendingOrder) {
                Text("SAVE ORDER")
                    .font(analogFont(20))
                    .tracking(2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.primary)
                    .foregroundStyle(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    // MARK: - Reorder / delete

    private func moveSteps(from source: IndexSet, to destination: Int) {
        var ids = orderedSteps.map(\.stepID)
        ids.move(fromOffsets: source, toOffset: destination)
        pendingOrder = ids
        selectedStepID = nil
    }

    private func savePendingOrder() {
        for (position, step) in orderedSteps.enumerated() {
            step.sortOrder = position
        }
        try? modelContext.save()
        pendingOrder = nil
    }

    private func cancelPendingOrder() {
        withAnimation { pendingOrder = nil }
    }

    /// Swipe-to-delete, after the receipt dialog has confirmed it.
    private func deleteStep(_ step: RunStep) {
        guard let live = liveStep(for: step) else { return }
        let remaining = steps.filter { $0.stepID != step.id }
        withAnimation {
            modelContext.delete(live)
            for (position, existing) in remaining.enumerated() {
                existing.sortOrder = position
            }
            pendingOrder?.removeAll { $0 == step.id }
            if selectedStepID == step.id { selectedStepID = nil }
        }
        try? modelContext.save()
    }

    /// The saved step behind a displayed one, by stable id.
    private func liveStep(for step: RunStep) -> RoutineStep? {
        steps.first { $0.stepID == step.id }
    }

    /// Inserts a fresh step after the displayed row at `index` (-1 for the
    /// front) and opens it. Written in terms of the *saved* order so a
    /// pending drag stays pending: the new step lands after the same
    /// neighbour in both.
    private func insertStep(after index: Int) {
        let displayed = orderedSteps
        let anchorID: UUID? = displayed.indices.contains(index) ? displayed[index].stepID : nil

        let step = RoutineStep(title: "New Step", durationSeconds: 5 * 60, autoNext: true, notes: "", sortOrder: 0)
        modelContext.insert(step)

        var saved = steps
        let savedPosition = anchorID.flatMap { id in saved.firstIndex { $0.stepID == id } }.map { $0 + 1 } ?? 0
        saved.insert(step, at: savedPosition)
        for (position, existing) in saved.enumerated() {
            existing.sortOrder = position
        }
        if var pending = pendingOrder {
            let position = anchorID.flatMap { pending.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            pending.insert(step.stepID, at: position)
            pendingOrder = pending
        }
        try? modelContext.save()
        editingStep = StepEditRequest(step: step, isNew: true)
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
        // Presented a beat after the step lands, and explicitly animated:
        // set synchronously inside the engine's tick it appeared with no
        // transition at all, already open on top of the new step.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard engine.isRunning, engine.currentIndex == index else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                notesRequest = NotesRequest(editing: false)
            }
        }
    }

}

// MARK: - Idle Step Row

private struct IdleStepRow: View {
    let step: RunStep
    let index: Int
    let currentIndex: Int
    let isRoutineComplete: Bool
    let isRoutineActive: Bool
    var isSelected = false
    var onEdit: () -> Void = {}
    var onStats: () -> Void = {}

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
            }

            Spacer(minLength: 8)

            if isSelected {
                HStack(spacing: 8) {
                    actionButton("pencil", label: "Edit step", action: onEdit)
                    actionButton("arrow.right", label: "Step stats", action: onStats)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            }
        }
        .opacity(isDone ? 0.5 : 1)
    }

    private func actionButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
            .padding(.leading, 10)
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
