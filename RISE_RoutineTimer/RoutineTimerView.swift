//
//  RoutineTimerView.swift
//  RISE_RoutineTimer
//
//  The runner tab. Timer state is based on Dates, not just tick counts, so it
//  can catch up after the app is backgrounded and opened again.
//

import SwiftUI
import UIKit

private enum FillDirection {
    case bottomToTop
}

// Same masking pattern as TwoMinRuleTimer: content is drawn twice at the exact
// same coordinates, and only the filling layer is masked. The fill moves; the
// text never does.
private struct InvertingFillView<Content: View>: View {
    let fillColor: Color
    let fillFraction: Double
    let direction: FillDirection
    @ViewBuilder let content: (Color) -> Content

    var body: some View {
        ZStack {
            ZStack {
                Color.white
                content(.black)
            }

            ZStack {
                fillColor
                content(.white)
            }
            .mask(maskShape)
        }
    }

    private var maskShape: some View {
        GeometryReader { geo in
            Color.black
                .frame(
                    width: geo.size.width,
                    height: geo.size.height * fillFraction
                )
                .frame(
                    width: geo.size.width,
                    height: geo.size.height,
                    alignment: .bottom
                )
        }
    }
}

struct RoutineTimerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("routineSoundsEnabled") private var soundsEnabled = true

    let steps: [RoutineStep]

    @State private var currentIndex = 0
    @State private var isRunning = false
    @State private var isComplete = false
    @State private var stepStartDate: Date?
    @State private var stepEndDate: Date?
    @State private var pausedRemainingSeconds: Int?
    @State private var routineStartDate: Date?
    @State private var pausedRoutineElapsedSeconds: Int?
    @State private var accumulatedRoutineDeltaSeconds = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            Group {
                if steps.isEmpty {
                    ContentUnavailableView(
                        "No Routine Steps",
                        systemImage: "list.bullet",
                        description: Text("Add a step in the Edit tab to start your routine.")
                    )
                } else if isRunning {
                    activeRoutineScreen
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            timerCard
                            notesCard
                            controls
                            settings
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Morning Routine")
            .toolbar(isRunning ? .hidden : .visible, for: .navigationBar)
            .toolbar(isRunning ? .hidden : .visible, for: .tabBar)
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: routineSignature) { _, _ in
            handleRoutineChanged()
        }
        .onAppear {
            setScreenAwake(isRunning)
        }
        .onDisappear {
            setScreenAwake(false)
        }
    }

    private var activeRoutineScreen: some View {
        GeometryReader { geometry in
            let checkDiameter = min(168, geometry.size.width * 0.43)
            let checkY = fixedCheckButtonY(diameter: checkDiameter, in: geometry)

            ZStack {
                InvertingFillView(
                    fillColor: .black,
                    fillFraction: currentStepFillProgress,
                    direction: .bottomToTop
                ) { textColor in
                    activeFixedContent(in: geometry, textColor: textColor)
                }
                .ignoresSafeArea()

                Button(action: nextStep) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 100, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: checkDiameter, height: checkDiameter)
                        .background(Circle().fill(.white))
                        .overlay(
                            Circle()
                                .stroke(.black.opacity(0.12), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .position(x: geometry.size.width / 2, y: checkY)
                .accessibilityLabel("Complete current step")
            }
        }
    }

    private func activeFixedContent(in geometry: GeometryProxy, textColor: Color) -> some View {
        ZStack(alignment: .topLeading) {
            activeHeader(color: textColor)
                .frame(width: max(180, geometry.size.width - 160))
                .position(
                    x: geometry.size.width / 2 + 36,
                    y: headerCenterY(in: geometry)
                )

            timerText(color: textColor)
                .frame(width: geometry.size.width)
                .position(x: geometry.size.width / 2, y: fixedTimerY(in: geometry))

            activeProgressRail(in: geometry, textColor: textColor)

            Text("NEXT: \(nextStepTitle.uppercased())")
                .font(analogFont(24))
                .tracking(2)
                .foregroundStyle(textColor.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: geometry.size.width * 0.58, alignment: .trailing)
                .position(
                    x: geometry.size.width - ((geometry.size.width * 0.58) / 2) - 16,
                    y: geometry.size.height - max(56, geometry.safeAreaInsets.bottom + 30)
                )
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }

    private func activeHeader(color: Color) -> some View {
        VStack(spacing: 14) {
            Text((currentStep?.title ?? "Routine").uppercased())
                .font(analogFont(40))
                .multilineTextAlignment(.center)
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(stepTimeRangeText)
                .font(analogFont(28))
                .foregroundStyle(color.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func timerText(color: Color) -> some View {
        Text(displayTime)
            .font(digitFont(96))
            .monospacedDigit()
            .foregroundStyle(color)
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    private func activeProgressRail(in geometry: GeometryProxy, textColor: Color) -> some View {
        let topY = max(150, geometry.safeAreaInsets.top + 116)
        let bottomY = geometry.size.height - max(126, geometry.safeAreaInsets.bottom + 96)
        let railHeight = max(120, bottomY - topY)
        let dotY = bottomY - (railHeight * routineProgressValue)

        return ZStack(alignment: .top) {
            Capsule()
                .fill(Color(white: 0.86))
                .frame(width: 50, height: railHeight)
                .overlay(
                    Capsule()
                        .stroke(Color(white: 0.72), lineWidth: 3)
                )

            Capsule()
                .fill(Color(white: 0.58))
                .frame(width: 50, height: railHeight * routineProgressValue)
                .frame(height: railHeight, alignment: .bottom)

            Circle()
                .fill(Color(red: 0.17, green: 0.56, blue: 0.68))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.92), lineWidth: 3)
                )
                .offset(y: dotY - topY - 14)

            Text(routineEndClockText)
                .font(analogFont(26))
                .foregroundStyle(textColor)
                .frame(width: 90, alignment: .leading)
                .offset(x: -4, y: -44)

            Text(routineStartClockText)
                .font(analogFont(24))
                .foregroundStyle(textColor)
                .frame(width: 90, alignment: .leading)
                .offset(x: -4, y: railHeight + 10)
        }
        .position(x: 68, y: topY + railHeight / 2)
    }

    private func headerCenterY(in geometry: GeometryProxy) -> CGFloat {
        max(168, geometry.safeAreaInsets.top + 142)
    }

    private func fixedTimerY(in geometry: GeometryProxy) -> CGFloat {
        let checkDiameter = min(168, geometry.size.width * 0.43)
        let checkY = fixedCheckButtonY(diameter: checkDiameter, in: geometry)
        return min(geometry.size.height * 0.43, checkY - (checkDiameter / 2) - 92)
    }

    private func fixedCheckButtonY(diameter: CGFloat, in geometry: GeometryProxy) -> CGFloat {
        let radius = diameter / 2
        let preferredY = geometry.size.height * 0.64
        let bottomLimit = geometry.size.height - geometry.safeAreaInsets.bottom - radius - 66
        return min(preferredY, bottomLimit)
    }

    private var timerCard: some View {
        VStack(spacing: 18) {
            Text(statusText)
                .font(analogFont(18))
                .foregroundStyle(isOvertime ? .orange : .secondary)

            Text(currentStep?.title ?? "Routine")
                .font(analogFont(40))
                .multilineTextAlignment(.center)

            Text(displayTime)
                .font(digitFont(82))
                .monospacedDigit()
                .foregroundStyle(isOvertime ? .orange : .primary)
                .minimumScaleFactor(0.65)

            ProgressView(value: progressValue)
                .tint(isOvertime ? .orange : .blue)

            VStack(spacing: 8) {
                LabeledContent("Task duration", value: plannedDurationText)
                LabeledContent("Next task", value: nextStepTitle)
            }
            .font(.callout)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var notesCard: some View {
        if let currentStep, !currentStep.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)

                Text(currentStep.notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            )
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button(action: toggleRunning) {
                Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack {
                Button(action: previousStep) {
                    Label("Previous", systemImage: "backward.fill")
                }
                .disabled(!canGoPrevious)

                Spacer()

                Button(action: resetRoutine) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                Spacer()

                Button(action: nextStep) {
                    Label("Next", systemImage: "forward.fill")
                }
                .disabled(isComplete)
            }
            .buttonStyle(.bordered)
        }
    }

    private var settings: some View {
        Toggle(isOn: $soundsEnabled) {
            Label("Sounds", systemImage: soundsEnabled ? "speaker.wave.2" : "speaker.slash")
        }
        .padding(.horizontal, 4)
    }

    private var currentStep: RoutineStep? {
        guard steps.indices.contains(currentIndex) else {
            return nil
        }

        return steps[currentIndex]
    }

    private var secondsRemaining: Int {
        guard let currentStep else {
            return 0
        }

        if isComplete {
            return 0
        }

        if let stepEndDate {
            return Int(ceil(stepEndDate.timeIntervalSince(now)))
        }

        return pausedRemainingSeconds ?? currentStep.durationSeconds
    }

    private var isOvertime: Bool {
        secondsRemaining < 0
    }

    private var displayTime: String {
        if isOvertime {
            return "+\(TimeFormatting.clockTime(from: secondsRemaining))"
        }

        return TimeFormatting.clockTime(from: secondsRemaining)
    }

    private var plannedDurationText: String {
        TimeFormatting.durationText(from: currentStep?.durationSeconds ?? 0)
    }

    private var nextStepTitle: String {
        guard steps.indices.contains(currentIndex + 1) else {
            return isComplete ? "Done" : "Routine complete"
        }

        return steps[currentIndex + 1].title
    }

    private var currentClockText: String {
        TimeFormatting.shortClockTime(from: now)
    }

    private var stepStartClockText: String {
        TimeFormatting.shortClockTime(from: displayedStepStartDate)
    }

    private var stepTimeRangeText: String {
        let start = TimeFormatting.shortClockTime(from: displayedStepStartDate)
        let end = TimeFormatting.shortClockTime(from: displayedStepEndDate)

        return "\(start) - \(end)"
    }

    private var displayedStepStartDate: Date {
        if let stepStartDate {
            return stepStartDate
        }

        if let stepEndDate, let currentStep {
            return stepEndDate.addingTimeInterval(TimeInterval(-currentStep.durationSeconds))
        }

        guard let currentStep else {
            return now
        }

        let remaining = pausedRemainingSeconds ?? currentStep.durationSeconds
        return now.addingTimeInterval(TimeInterval(-(currentStep.durationSeconds - remaining)))
    }

    private var displayedStepEndDate: Date {
        if let stepEndDate {
            return stepEndDate
        }

        return displayedStepStartDate.addingTimeInterval(TimeInterval(currentStep?.durationSeconds ?? 0))
    }

    private var statusText: String {
        if isComplete {
            return "Complete"
        }

        if isOvertime {
            return "Overtime"
        }

        return isRunning ? "Running" : "Paused"
    }

    private var progressValue: Double {
        guard let currentStep else {
            return 0
        }

        guard currentStep.durationSeconds > 0 else {
            return 1
        }

        let elapsed = currentStep.durationSeconds - max(0, secondsRemaining)
        return min(1, max(0, Double(elapsed) / Double(currentStep.durationSeconds)))
    }

    private var currentStepFillProgress: Double {
        guard let currentStep else {
            return 0
        }

        let elapsed = max(0, currentStep.durationSeconds - secondsRemaining)
        return min(1, Double(elapsed) / Double(currentStep.durationSeconds))
    }

    private var routineProgressValue: Double {
        let adjustedDuration = max(1, adjustedRoutineDurationSeconds)
        return min(1, max(0, Double(routineElapsedSeconds) / Double(adjustedDuration)))
    }

    private var routineElapsedSeconds: Int {
        if let routineStartDate, isRunning {
            return max(0, Int(now.timeIntervalSince(routineStartDate)))
        }

        return max(0, pausedRoutineElapsedSeconds ?? elapsedSecondsBeforeCurrentStep)
    }

    private var plannedRoutineDurationSeconds: Int {
        steps.reduce(0) { total, step in
            total + step.durationSeconds
        }
    }

    private var adjustedRoutineDurationSeconds: Int {
        max(1, plannedRoutineDurationSeconds + accumulatedRoutineDeltaSeconds + currentOvertimeSeconds)
    }

    private var currentOvertimeSeconds: Int {
        max(0, -secondsRemaining)
    }

    private var elapsedSecondsBeforeCurrentStep: Int {
        guard currentIndex > 0 else {
            return 0
        }

        return steps.prefix(currentIndex).reduce(0) { total, step in
            total + step.durationSeconds
        }
    }

    private var displayedRoutineStartDate: Date {
        if let routineStartDate {
            return routineStartDate
        }

        return now.addingTimeInterval(TimeInterval(-routineElapsedSeconds))
    }

    private var displayedRoutineEndDate: Date {
        displayedRoutineStartDate.addingTimeInterval(TimeInterval(adjustedRoutineDurationSeconds))
    }

    private var routineStartClockText: String {
        TimeFormatting.shortClockTime(from: displayedRoutineStartDate)
    }

    private var routineEndClockText: String {
        TimeFormatting.shortClockTime(from: displayedRoutineEndDate)
    }

    private var primaryButtonTitle: String {
        if isComplete {
            return "Start Over"
        }

        return isRunning ? "Pause" : "Start"
    }

    private var primaryButtonIcon: String {
        if isComplete {
            return "arrow.counterclockwise"
        }

        return isRunning ? "pause.fill" : "play.fill"
    }

    private var canGoPrevious: Bool {
        currentIndex > 0 && !steps.isEmpty
    }

    // Any edit to the routine should reschedule notifications if the timer is running.
    private var routineSignature: String {
        steps.map { step in
            "\(step.sortOrder)|\(step.title)|\(step.durationSeconds)|\(step.autoNext)|\(step.notes)"
        }
        .joined(separator: "::")
    }

    private func toggleRunning() {
        if isComplete {
            resetRoutine()
            startRoutine()
        } else if isRunning {
            pauseRoutine()
        } else {
            startRoutine()
        }
    }

    private func startRoutine() {
        guard let currentStep else {
            return
        }

        now = Date()

        // If resuming, rebuild the original start date from the saved remaining time.
        let remaining = pausedRemainingSeconds ?? currentStep.durationSeconds
        stepEndDate = now.addingTimeInterval(TimeInterval(remaining))
        stepStartDate = stepEndDate?.addingTimeInterval(TimeInterval(-currentStep.durationSeconds))
        routineStartDate = now.addingTimeInterval(TimeInterval(-(pausedRoutineElapsedSeconds ?? elapsedSecondsBeforeCurrentStep)))
        pausedRemainingSeconds = nil
        pausedRoutineElapsedSeconds = nil
        isComplete = false
        isRunning = true

        setScreenAwake(true)
        runCountdownTask()
        requestPermissionAndScheduleNotifications()
    }

    private func pauseRoutine() {
        pausedRemainingSeconds = secondsRemaining
        pausedRoutineElapsedSeconds = routineElapsedSeconds
        timerTask?.cancel()
        timerTask = nil
        stepStartDate = nil
        stepEndDate = nil
        routineStartDate = nil
        isRunning = false

        setScreenAwake(false)
        RoutineNotificationManager.cancelRoutineNotifications()
    }

    private func resetRoutine() {
        currentIndex = 0
        isRunning = false
        isComplete = false
        timerTask?.cancel()
        timerTask = nil
        stepStartDate = nil
        stepEndDate = nil
        pausedRemainingSeconds = nil
        routineStartDate = nil
        pausedRoutineElapsedSeconds = nil
        accumulatedRoutineDeltaSeconds = 0
        now = Date()

        setScreenAwake(false)
        RoutineNotificationManager.cancelRoutineNotifications()
    }

    private func nextStep() {
        guard !steps.isEmpty else {
            resetRoutine()
            return
        }

        recordCurrentStepTimingDelta()

        if steps.indices.contains(currentIndex + 1) {
            currentIndex += 1
            startCurrentStepFromBeginning(playSound: isRunning)
        } else {
            completeRoutine(playSound: true)
        }
    }

    private func previousStep() {
        guard canGoPrevious else {
            return
        }

        currentIndex -= 1
        startCurrentStepFromBeginning(playSound: false)
    }

    private func startCurrentStepFromBeginning(playSound: Bool) {
        now = Date()
        pausedRemainingSeconds = currentStep?.durationSeconds

        if isRunning {
            stepStartDate = now
            stepEndDate = now.addingTimeInterval(TimeInterval(currentStep?.durationSeconds ?? 0))
            if routineStartDate == nil {
                routineStartDate = now.addingTimeInterval(TimeInterval(-(elapsedSecondsBeforeCurrentStep + accumulatedRoutineDeltaSeconds)))
            }
            pausedRemainingSeconds = nil
            pausedRoutineElapsedSeconds = nil
            requestPermissionAndScheduleNotifications()
        } else {
            stepStartDate = nil
            stepEndDate = nil
            pausedRoutineElapsedSeconds = elapsedSecondsBeforeCurrentStep + accumulatedRoutineDeltaSeconds
        }

        isComplete = false

        if playSound {
            RoutineSoundPlayer.playStepTransition(isEnabled: soundsEnabled)
        }
    }

    private func advanceAutoNextStepsIfNeeded() {
        guard isRunning, let originalEndDate = stepEndDate, !steps.isEmpty else {
            return
        }

        var index = currentIndex
        var startDate = stepStartDate ?? originalEndDate.addingTimeInterval(TimeInterval(-(currentStep?.durationSeconds ?? 0)))
        var endDate = originalEndDate
        var didAdvance = false

        while steps.indices.contains(index) {
            let step = steps[index]

            guard now >= endDate else {
                break
            }

            guard step.autoNext else {
                break
            }

            let nextIndex = index + 1

            guard steps.indices.contains(nextIndex) else {
                completeRoutine(playSound: true)
                return
            }

            let nextStep = steps[nextIndex]
            index = nextIndex
            startDate = endDate
            endDate = startDate.addingTimeInterval(TimeInterval(nextStep.durationSeconds))
            didAdvance = true
        }

        if didAdvance {
            currentIndex = index
            stepStartDate = startDate
            stepEndDate = endDate
            pausedRemainingSeconds = nil
            RoutineSoundPlayer.playStepTransition(isEnabled: soundsEnabled)
            requestPermissionAndScheduleNotifications()
        }
    }

    private func completeRoutine(playSound: Bool) {
        isRunning = false
        isComplete = true
        timerTask?.cancel()
        timerTask = nil
        stepStartDate = nil
        stepEndDate = nil
        pausedRemainingSeconds = 0
        pausedRoutineElapsedSeconds = adjustedRoutineDurationSeconds
        routineStartDate = nil

        setScreenAwake(false)
        RoutineNotificationManager.cancelRoutineNotifications()

        if playSound {
            RoutineSoundPlayer.playCompletion(isEnabled: soundsEnabled)
        }
    }

    private func runCountdownTask() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                now = Date()
                advanceAutoNextStepsIfNeeded()

                guard isRunning else {
                    return
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshFromBackground() {
        guard isRunning else {
            return
        }

        now = Date()
        advanceAutoNextStepsIfNeeded()
        runCountdownTask()
    }

    private func recordCurrentStepTimingDelta() {
        guard let currentStep else {
            return
        }

        let elapsedSeconds = max(0, currentStep.durationSeconds - secondsRemaining)
        accumulatedRoutineDeltaSeconds += elapsedSeconds - currentStep.durationSeconds
    }

    private func requestPermissionAndScheduleNotifications() {
        guard isRunning, let stepStartDate else {
            return
        }

        Task {
            await RoutineNotificationManager.requestPermissionIfNeeded()

            if isRunning {
                RoutineNotificationManager.scheduleNotifications(
                    steps: steps,
                    currentIndex: currentIndex,
                    stepStartDate: stepStartDate
                )
            }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            refreshFromBackground()
            setScreenAwake(isRunning)
        case .inactive, .background:
            setScreenAwake(false)
        @unknown default:
            setScreenAwake(false)
        }
    }

    private func handleRoutineChanged() {
        guard !steps.isEmpty else {
            resetRoutine()
            return
        }

        if currentIndex >= steps.count {
            currentIndex = max(0, steps.count - 1)
            startCurrentStepFromBeginning(playSound: false)
        }

        if isRunning {
            requestPermissionAndScheduleNotifications()
        }
    }

    private func setScreenAwake(_ shouldStayAwake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = shouldStayAwake
    }
}
