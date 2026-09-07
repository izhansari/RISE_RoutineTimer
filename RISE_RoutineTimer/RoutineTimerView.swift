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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(RoutineAlertCoordinator.soundsKey) private var soundsEnabled = true
    @AppStorage(RoutineAlertCoordinator.voiceKey) private var voiceEnabled = true
    @AppStorage(TargetSchedule.targetKey) private var targetMinutes = TargetSchedule.none

    let steps: [RoutineStep]

    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]

    @State private var showingNotes = false
    @State private var confirmingEnd = false
    @State private var summaryResult: SessionResult?

    var body: some View {
        NavigationStack {
            Group {
                if steps.isEmpty && engine.run == nil {
                    ContentUnavailableView(
                        "No Routine Steps",
                        systemImage: "list.bullet",
                        description: Text("Add a step in the Routine tab to start.")
                    )
                } else if engine.isRunning {
                    activeRoutineScreen
                } else {
                    idleScreen
                }
            }
            .navigationTitle("Morning Routine")
            .toolbar(engine.isRunning ? .hidden : .visible, for: .navigationBar)
            .toolbar(engine.isRunning ? .hidden : .visible, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    alertsMenu
                }
            }
        }
        .onChange(of: engine.isRunning, initial: true) { _, running in
            setScreenAwake(running)
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
        .onChange(of: scenePhase) { _, newPhase in
            setScreenAwake(newPhase == .active && engine.isRunning)
        }
        .onDisappear {
            setScreenAwake(false)
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

                    let rows = displayedSteps
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, step in
                        IdleStepRow(
                            step: step,
                            index: index,
                            currentIndex: engine.currentIndex,
                            isRoutineComplete: engine.isComplete,
                            isRoutineActive: engine.run != nil
                        )

                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 1.5, height: 20)
                                .padding(.leading, 14)
                        }
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

                if engine.isPaused {
                    Button("END ROUTINE", role: .destructive) { confirmingEnd = true }
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
            }
            .padding(.bottom, 10)
        }
        .confirmationDialog("End this routine?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End Routine", role: .destructive) { engine.abandon() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("You'll start from the first step next time.")
        }
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
            onShowNotes: { showingNotes = true },
            onEnd: { confirmingEnd = true }
        )
        .sheet(isPresented: $showingNotes) {
            notesSheet
        }
        .confirmationDialog("End this routine?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End Routine", role: .destructive) { engine.abandon() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("You'll start from the first step next time.")
        }
    }

    private var notesSheet: some View {
        ScrollView {
            Text(engine.currentStep?.notes ?? "")
                .font(analogFont(22))
                .multilineTextAlignment(.center)
                .padding(32)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func setScreenAwake(_ shouldStayAwake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = shouldStayAwake
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
        HStack(alignment: .top, spacing: 14) {
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
                        .font(.system(size: isCurrent ? 18 : 16))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(.systemBackground)))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(isCurrent ? 1 : 0.3), lineWidth: 1.5))
                } else if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(.systemBackground))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color(.systemBackground) : .secondary)
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(analogFont(isCurrent ? 26 : 22))
                    .foregroundStyle(isDone ? .secondary : .primary)

                HStack(spacing: 10) {
                    Text(TimeFormatting.durationText(from: step.durationSeconds))
                        .font(analogFont(16))
                        .foregroundStyle(.secondary)

                    if !step.autoNext {
                        Text("MANUAL")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
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
        .padding(.vertical, 10)
        .opacity(isDone ? 0.5 : 1)
    }
}
