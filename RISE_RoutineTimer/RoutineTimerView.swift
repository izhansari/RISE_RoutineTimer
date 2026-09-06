//
//  RoutineTimerView.swift
//  RISE_RoutineTimer
//
//  The "Run" tab. Idle screen (ready / paused / complete) and the active
//  timer screen. All timing comes from `RoutineEngine`; this file only draws.
//

import SwiftUI
import UIKit

/// White page that fills black from the bottom as the step progresses.
/// Content is drawn once in white with a difference blend, so it reads black
/// on the white part and white on the black part without duplicating views.
private struct InvertingFillView<Content: View>: View {
    let fillFraction: Double
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.white
            GeometryReader { geo in
                Color.black
                    .frame(height: geo.size.height * fillFraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            content()
                .blendMode(.difference)
        }
    }
}

struct RoutineTimerView: View {
    @Environment(RoutineEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(RoutineAlertCoordinator.soundsKey) private var soundsEnabled = true
    @AppStorage(RoutineAlertCoordinator.voiceKey) private var voiceEnabled = true

    let steps: [RoutineStep]

    @State private var showingNotes = false
    @State private var confirmingEnd = false

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
                    .padding(.bottom, idleSummaryLine == nil ? 20 : 6)

                    if let idleSummaryLine {
                        Text(idleSummaryLine)
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
        GeometryReader { geo in
            let checkDiameter = min(144, geo.size.width * 0.37)
            let undoDiameter = checkDiameter * 0.42
            let buttonY = min(
                geo.size.height * 0.64,
                geo.size.height - geo.safeAreaInsets.bottom - checkDiameter / 2 - 52
            )

            ZStack {
                InvertingFillView(fillFraction: engine.currentStepFillProgress) {
                    activeContent(geo: geo)
                }
                .ignoresSafeArea()

                Button {
                    engine.completeCurrentStep()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: checkDiameter * 0.46, weight: .medium))
                        .foregroundStyle(Color.black)
                        .frame(width: checkDiameter, height: checkDiameter)
                        .background(Circle().fill(Color.white))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete step")
                .position(x: geo.size.width / 2, y: buttonY)

                if engine.currentIndex > 0 {
                    Button {
                        engine.undoLastStep()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: undoDiameter * 0.4, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.6))
                            .frame(width: undoDiameter, height: undoDiameter)
                            .background(Circle().fill(Color.white))
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go back to previous step")
                    .position(
                        x: geo.size.width / 2 - checkDiameter / 2 - 22 - undoDiameter / 2,
                        y: buttonY
                    )
                }
            }
        }
        .sheet(isPresented: $showingNotes) {
            ScrollView {
                Text(engine.currentStep?.notes ?? "")
                    .font(analogFont(22))
                    .multilineTextAlignment(.center)
                    .padding(32)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("End this routine?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End Routine", role: .destructive) { engine.abandon() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("You'll start from the first step next time.")
        }
    }

    private func activeContent(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                activeIconButton("xmark", label: "End routine") { confirmingEnd = true }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(engine.steps.indices, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(
                                i < engine.currentIndex ? 0.7 : i == engine.currentIndex ? 1.0 : 0.2
                            ))
                            .frame(width: i == engine.currentIndex ? 26 : 10, height: 5)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: engine.currentIndex)

                Spacer()

                activeIconButton("pause.fill", label: "Pause routine") { engine.pause() }
            }
            .padding(.top, geo.safeAreaInsets.top + 8)
            .padding(.horizontal, 20)

            Spacer().frame(height: geo.size.height * 0.06)

            VStack(spacing: 10) {
                Text((engine.currentStep?.title ?? "").uppercased())
                    .font(analogFont(44))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)

                Text(stepTimeRangeText)
                    .font(analogFont(22))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 28)

            Spacer().frame(height: geo.size.height * 0.05)

            Text(displayTime)
                .font(digitFont(88))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .accessibilityLabel(engine.isOvertime ? "\(displayTime) over" : "\(displayTime) remaining")

            Spacer()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routineStartClockText)
                        .font(analogFont(17))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(routineEndClockText)
                        .font(analogFont(21))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(TimeFormatting.scheduleDeltaText(from: engine.scheduleDeltaSeconds))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 2)
                }

                Spacer()

                if engine.currentStep?.hasNotes == true {
                    Button { showingNotes = true } label: {
                        Image(systemName: "note.text")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show notes")
                    .padding(.trailing, 14)
                }

                Text("NEXT: \(nextStepTitle.uppercased())")
                    .font(analogFont(19))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: geo.size.width * 0.5, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, max(geo.safeAreaInsets.bottom + 24, 36))
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    private func activeIconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Text

    private var displayTime: String {
        if engine.isOvertime {
            return "+\(TimeFormatting.clockTime(from: engine.overtimeSeconds))"
        }
        return TimeFormatting.clockTime(from: engine.secondsRemaining)
    }

    private var nextStepTitle: String {
        engine.nextStep?.title ?? "Last step"
    }

    private var stepTimeRangeText: String {
        let start = TimeFormatting.shortClockTime(from: engine.stepStartDate)
        let end = TimeFormatting.shortClockTime(from: engine.stepEndDate)
        return "\(start) – \(end)"
    }

    private var routineStartClockText: String {
        guard let start = engine.routineStartDate else { return "" }
        return TimeFormatting.shortClockTime(from: start)
    }

    private var routineEndClockText: String {
        TimeFormatting.shortClockTime(from: engine.projectedEndDate)
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

                if isDone {
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
