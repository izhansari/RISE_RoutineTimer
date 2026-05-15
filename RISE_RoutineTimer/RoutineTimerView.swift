import SwiftUI
import UIKit

private enum FillDirection {
    case bottomToTop
}

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
                .frame(width: geo.size.width, height: geo.size.height * fillFraction)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
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
                    idleScreen
                }
            }
            .navigationTitle("Morning Routine")
            .toolbar(isRunning ? .hidden : .visible, for: .navigationBar)
            .toolbar(isRunning ? .hidden : .visible, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { soundsEnabled.toggle() }) {
                        Image(systemName: soundsEnabled ? "speaker.wave.2" : "speaker.slash")
                    }
                    .accessibilityLabel(soundsEnabled ? "Mute sounds" : "Enable sounds")
                }
            }
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

    // MARK: - Idle Screen

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
                        Text(TimeFormatting.durationText(from: plannedRoutineDurationSeconds))
                            .font(analogFont(30))
                    }
                    .padding(.vertical, 20)

                    Divider().padding(.bottom, 12)

                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        IdleStepRow(
                            step: step,
                            index: index,
                            currentIndex: currentIndex,
                            isRoutineComplete: isComplete
                        )

                        if index < steps.count - 1 {
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

            VStack(spacing: 0) {
                Divider()

                VStack(spacing: 10) {
                    Button(action: toggleRunning) {
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

                    HStack(spacing: 0) {
                        Button(action: previousStep) {
                            Label("Back", systemImage: "backward.fill")
                        }
                        .disabled(!canGoPrevious)
                        .frame(maxWidth: .infinity)

                        Button(action: resetRoutine) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .frame(maxWidth: .infinity)

                        Button(action: nextStep) {
                            Label("Skip", systemImage: "forward.fill")
                        }
                        .disabled(isComplete)
                        .frame(maxWidth: .infinity)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
        }
    }

    private var idleStatusLabel: String {
        if isComplete { return "COMPLETE" }
        let inProgress = pausedRemainingSeconds != nil || pausedRoutineElapsedSeconds != nil || currentIndex > 0
        return inProgress ? "PAUSED" : "READY"
    }

    // MARK: - Active Screen

    private var activeRoutineScreen: some View {
        GeometryReader { geo in
            ZStack {
                InvertingFillView(
                    fillColor: .black,
                    fillFraction: currentStepFillProgress,
                    direction: .bottomToTop
                ) { textColor in
                    activeContent(textColor: textColor, geo: geo)
                }
                .ignoresSafeArea()

                let d = min(144, geo.size.width * 0.37)
                Button(action: nextStep) {
                    Image(systemName: "checkmark")
                        .font(.system(size: d * 0.46, weight: .medium))
                        .foregroundStyle(Color.black)
                        .frame(width: d, height: d)
                        .background(Circle().fill(Color.white))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete step")
                .position(
                    x: geo.size.width / 2,
                    y: min(
                        geo.size.height * 0.64,
                        geo.size.height - geo.safeAreaInsets.bottom - d / 2 - 52
                    )
                )
            }
        }
    }

    private func activeContent(textColor: Color, geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(textColor.opacity(
                            i < currentIndex ? 0.7 : i == currentIndex ? 1.0 : 0.2
                        ))
                        .frame(width: i == currentIndex ? 26 : 10, height: 5)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentIndex)
            .padding(.top, geo.safeAreaInsets.top + 16)
            .padding(.horizontal, 28)

            Spacer().frame(height: geo.size.height * 0.08)

            VStack(spacing: 10) {
                Text((currentStep?.title ?? "").uppercased())
                    .font(analogFont(44))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(textColor)
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)

                Text(stepTimeRangeText)
                    .font(analogFont(22))
                    .foregroundStyle(textColor.opacity(0.6))
            }
            .padding(.horizontal, 28)

            Spacer().frame(height: geo.size.height * 0.05)

            Text(displayTime)
                .font(digitFont(88))
                .monospacedDigit()
                .foregroundStyle(textColor)
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)

            Spacer()

            if let notes = currentStep?.notes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(analogFont(18))
                    .foregroundStyle(textColor.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 14)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routineStartClockText)
                        .font(analogFont(17))
                        .foregroundStyle(textColor.opacity(0.35))
                    Text(routineEndClockText)
                        .font(analogFont(21))
                        .foregroundStyle(textColor.opacity(0.6))
                }

                Spacer()

                Text("NEXT: \(nextStepTitle.uppercased())")
                    .font(analogFont(19))
                    .tracking(1.5)
                    .foregroundStyle(textColor.opacity(0.5))
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

    // MARK: - Computed Properties

    private var currentStep: RoutineStep? {
        guard steps.indices.contains(currentIndex) else { return nil }
        return steps[currentIndex]
    }

    private var secondsRemaining: Int {
        guard let currentStep else { return 0 }
        if isComplete { return 0 }
        if let stepEndDate { return Int(ceil(stepEndDate.timeIntervalSince(now))) }
        return pausedRemainingSeconds ?? currentStep.durationSeconds
    }

    private var isOvertime: Bool { secondsRemaining < 0 }

    private var displayTime: String {
        if isOvertime { return "+\(TimeFormatting.clockTime(from: secondsRemaining))" }
        return TimeFormatting.clockTime(from: secondsRemaining)
    }

    private var nextStepTitle: String {
        guard steps.indices.contains(currentIndex + 1) else {
            return isComplete ? "Done" : "Routine complete"
        }
        return steps[currentIndex + 1].title
    }

    private var stepTimeRangeText: String {
        let start = TimeFormatting.shortClockTime(from: displayedStepStartDate)
        let end = TimeFormatting.shortClockTime(from: displayedStepEndDate)
        return "\(start) – \(end)"
    }

    private var displayedStepStartDate: Date {
        if let stepStartDate { return stepStartDate }
        if let stepEndDate, let currentStep {
            return stepEndDate.addingTimeInterval(TimeInterval(-currentStep.durationSeconds))
        }
        guard let currentStep else { return now }
        let remaining = pausedRemainingSeconds ?? currentStep.durationSeconds
        return now.addingTimeInterval(TimeInterval(-(currentStep.durationSeconds - remaining)))
    }

    private var displayedStepEndDate: Date {
        if let stepEndDate { return stepEndDate }
        return displayedStepStartDate.addingTimeInterval(TimeInterval(currentStep?.durationSeconds ?? 0))
    }

    private var currentStepFillProgress: Double {
        guard let currentStep else { return 0 }
        let elapsed = max(0, currentStep.durationSeconds - secondsRemaining)
        return min(1, Double(elapsed) / Double(currentStep.durationSeconds))
    }

    private var routineElapsedSeconds: Int {
        if let routineStartDate, isRunning {
            return max(0, Int(now.timeIntervalSince(routineStartDate)))
        }
        return max(0, pausedRoutineElapsedSeconds ?? elapsedSecondsBeforeCurrentStep)
    }

    private var plannedRoutineDurationSeconds: Int {
        steps.reduce(0) { $0 + $1.durationSeconds }
    }

    private var adjustedRoutineDurationSeconds: Int {
        max(1, plannedRoutineDurationSeconds + accumulatedRoutineDeltaSeconds + currentOvertimeSeconds)
    }

    private var currentOvertimeSeconds: Int { max(0, -secondsRemaining) }

    private var elapsedSecondsBeforeCurrentStep: Int {
        guard currentIndex > 0 else { return 0 }
        return steps.prefix(currentIndex).reduce(0) { $0 + $1.durationSeconds }
    }

    private var displayedRoutineStartDate: Date {
        if let routineStartDate { return routineStartDate }
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
        if isComplete { return "Start Over" }
        return isRunning ? "Pause" : "Start"
    }

    private var primaryButtonIcon: String {
        if isComplete { return "arrow.counterclockwise" }
        return isRunning ? "pause.fill" : "play.fill"
    }

    private var canGoPrevious: Bool { currentIndex > 0 && !steps.isEmpty }

    private var routineSignature: String {
        steps.map { "\($0.sortOrder)|\($0.title)|\($0.durationSeconds)|\($0.autoNext)|\($0.notes)" }
             .joined(separator: "::")
    }

    // MARK: - Actions

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
        guard let currentStep else { return }
        now = Date()
        let remaining = pausedRemainingSeconds ?? currentStep.durationSeconds
        stepEndDate = now.addingTimeInterval(TimeInterval(remaining))
        stepStartDate = stepEndDate?.addingTimeInterval(TimeInterval(-currentStep.durationSeconds))
        routineStartDate = now.addingTimeInterval(
            TimeInterval(-(pausedRoutineElapsedSeconds ?? elapsedSecondsBeforeCurrentStep))
        )
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
        guard !steps.isEmpty else { resetRoutine(); return }
        recordCurrentStepTimingDelta()
        if steps.indices.contains(currentIndex + 1) {
            currentIndex += 1
            startCurrentStepFromBeginning(playSound: isRunning)
        } else {
            completeRoutine(playSound: true)
        }
    }

    private func previousStep() {
        guard canGoPrevious else { return }
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
                routineStartDate = now.addingTimeInterval(
                    TimeInterval(-(elapsedSecondsBeforeCurrentStep + accumulatedRoutineDeltaSeconds))
                )
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
        if playSound { RoutineSoundPlayer.playStepTransition(isEnabled: soundsEnabled) }
    }

    private func advanceAutoNextStepsIfNeeded() {
        guard isRunning, let originalEndDate = stepEndDate, !steps.isEmpty else { return }
        var index = currentIndex
        var startDate = stepStartDate ?? originalEndDate.addingTimeInterval(
            TimeInterval(-(currentStep?.durationSeconds ?? 0))
        )
        var endDate = originalEndDate
        var didAdvance = false

        while steps.indices.contains(index) {
            let step = steps[index]
            guard now >= endDate else { break }
            guard step.autoNext else { break }
            let nextIndex = index + 1
            guard steps.indices.contains(nextIndex) else {
                completeRoutine(playSound: true)
                return
            }
            let next = steps[nextIndex]
            index = nextIndex
            startDate = endDate
            endDate = startDate.addingTimeInterval(TimeInterval(next.durationSeconds))
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
        if playSound { RoutineSoundPlayer.playCompletion(isEnabled: soundsEnabled) }
    }

    private func runCountdownTask() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                now = Date()
                advanceAutoNextStepsIfNeeded()
                guard isRunning else { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshFromBackground() {
        guard isRunning else { return }
        now = Date()
        advanceAutoNextStepsIfNeeded()
        runCountdownTask()
    }

    private func recordCurrentStepTimingDelta() {
        guard let currentStep else { return }
        let elapsed = max(0, currentStep.durationSeconds - secondsRemaining)
        accumulatedRoutineDeltaSeconds += elapsed - currentStep.durationSeconds
    }

    private func requestPermissionAndScheduleNotifications() {
        guard isRunning, let stepStartDate else { return }
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
        guard !steps.isEmpty else { resetRoutine(); return }
        if currentIndex >= steps.count {
            currentIndex = max(0, steps.count - 1)
            startCurrentStepFromBeginning(playSound: false)
        }
        if isRunning { requestPermissionAndScheduleNotifications() }
    }

    private func setScreenAwake(_ shouldStayAwake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = shouldStayAwake
    }
}

// MARK: - Idle Step Row

private struct IdleStepRow: View {
    let step: RoutineStep
    let index: Int
    let currentIndex: Int
    let isRoutineComplete: Bool

    private var isDone: Bool { isRoutineComplete || index < currentIndex }
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

                if isCurrent, !step.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
