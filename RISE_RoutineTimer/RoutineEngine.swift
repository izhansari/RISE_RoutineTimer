//
//  RoutineEngine.swift
//  RISE_RoutineTimer
//
//  All timer logic lives here, independent of SwiftUI. Every computed value
//  is derived from `run` and `now`, so the engine can be unit tested with
//  synthetic dates and restored after the app is killed.
//

import Foundation
import Observation

protocol RunStore {
    func load() -> RoutineRun?
    func save(_ run: RoutineRun?)
}

final class UserDefaultsRunStore: RunStore {
    private let key = "activeRoutineRun"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RoutineRun? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RoutineRun.self, from: data)
    }

    func save(_ run: RoutineRun?) {
        guard let run, let data = try? JSONEncoder().encode(run) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

final class InMemoryRunStore: RunStore {
    var stored: RoutineRun?
    func load() -> RoutineRun? { stored }
    func save(_ run: RoutineRun?) { stored = run }
}

@Observable
final class RoutineEngine {
    enum Event: Equatable {
        case started
        case resumed
        case paused
        case stepStarted(index: Int, auto: Bool)
        case steppedBack(index: Int)
        case overtimeStarted(index: Int)
        case completed(SessionResult)
        case abandoned(SessionResult)
        case reset
    }

    /// A paused or running run older than this is dropped on launch.
    static let staleRunInterval: TimeInterval = 12 * 60 * 60
    static let overtimeNudgeMinutes = [1, 3, 5, 10]

    private(set) var run: RoutineRun?
    private(set) var now: Date

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored private let store: RunStore?
    @ObservationIgnored private let usesWallClock: Bool
    @ObservationIgnored private var clockTask: Task<Void, Never>?

    init(store: RunStore? = UserDefaultsRunStore(), usesWallClock: Bool = true, now: Date = Date()) {
        self.store = store
        self.usesWallClock = usesWallClock
        self.now = now

        if let restored = store?.load() {
            let isStale = now.timeIntervalSince(restored.startedAt) > Self.staleRunInterval
            if restored.phase == .complete || isStale {
                store?.save(nil)
            } else {
                run = restored
                if restored.phase == .running {
                    startClock()
                }
            }
        }
    }

    // MARK: - State

    var phase: RoutineRun.Phase? { run?.phase }
    var isRunning: Bool { run?.phase == .running }
    var isPaused: Bool { run?.phase == .paused }
    var isComplete: Bool { run?.phase == .complete }
    var hasActiveRun: Bool { isRunning || isPaused }

    var steps: [RunStep] { run?.steps ?? [] }
    var currentIndex: Int { run?.currentIndex ?? 0 }
    var results: [StepResult] { run?.results ?? [] }

    var currentStep: RunStep? {
        guard let run, run.phase != .complete, run.steps.indices.contains(run.currentIndex) else { return nil }
        return run.steps[run.currentIndex]
    }

    var nextStep: RunStep? {
        guard let run, run.steps.indices.contains(run.currentIndex + 1) else { return nil }
        return run.steps[run.currentIndex + 1]
    }

    var isOnLastStep: Bool {
        guard let run else { return false }
        return run.currentIndex == run.steps.count - 1
    }

    // MARK: - Time math

    func stepElapsed(at date: Date) -> TimeInterval {
        guard let run else { return 0 }
        return Self.elapsed(of: run, at: date)
    }

    var stepElapsed: TimeInterval { stepElapsed(at: now) }

    /// Whole seconds left on the current step. Negative once in overtime.
    var secondsRemaining: Int {
        guard let step = currentStep else { return 0 }
        return Int((Double(step.durationSeconds) - stepElapsed).rounded(.up))
    }

    var isOvertime: Bool {
        guard let step = currentStep else { return false }
        return stepElapsed >= Double(step.durationSeconds)
    }

    var overtimeSeconds: Int {
        guard let step = currentStep else { return 0 }
        return max(0, Int((stepElapsed - Double(step.durationSeconds)).rounded(.down)))
    }

    var currentStepFillProgress: Double {
        guard let step = currentStep, step.durationSeconds > 0 else { return 0 }
        return min(1, stepElapsed / Double(step.durationSeconds))
    }

    var stepStartDate: Date { now.addingTimeInterval(-stepElapsed) }

    var stepEndDate: Date {
        stepStartDate.addingTimeInterval(TimeInterval(currentStep?.durationSeconds ?? 0))
    }

    var routineStartDate: Date? { run?.startedAt }

    var plannedTotalSeconds: Int { run?.plannedSeconds ?? 0 }

    var completedActualSeconds: Int { results.reduce(0) { $0 + $1.actualSeconds } }

    /// Time spent doing steps, excluding pauses.
    var activeElapsedSeconds: Int {
        completedActualSeconds + Int(stepElapsed.rounded(.down))
    }

    /// Positive means behind plan, negative means ahead.
    var scheduleDeltaSeconds: Int {
        results.reduce(0) { $0 + $1.deltaSeconds } + overtimeSeconds
    }

    /// Planned seconds still to go: the rest of this step (never negative) plus every later step.
    var remainingPlannedSeconds: Int {
        guard let run, let step = currentStep else { return 0 }
        let currentRemaining = max(0, Double(step.durationSeconds) - stepElapsed)
        let following = run.steps.dropFirst(run.currentIndex + 1).reduce(0) { $0 + $1.durationSeconds }
        return Int(currentRemaining.rounded(.up)) + following
    }

    var projectedEndDate: Date {
        if let run, run.phase == .complete, let ended = run.endedAt {
            return ended
        }
        return now.addingTimeInterval(TimeInterval(remainingPlannedSeconds))
    }

    var pausedSeconds: Int {
        guard let run else { return 0 }
        var total = run.totalPausedSeconds
        if run.phase == .paused, let pausedAt = run.pausedAt {
            total += max(0, now.timeIntervalSince(pausedAt))
        }
        return Int(total.rounded())
    }

    // MARK: - Actions

    func start(steps: [RunStep], at date: Date = Date()) {
        guard !steps.isEmpty else { return }
        now = date
        run = RoutineRun(
            steps: steps,
            phase: .running,
            currentIndex: 0,
            startedAt: date,
            endedAt: nil,
            stepAccumulated: 0,
            stepResumedAt: date,
            pausedAt: nil,
            totalPausedSeconds: 0,
            results: [],
            overtimeAnnounced: false
        )
        persist()
        startClock()
        emit(.started)
        emit(.stepStarted(index: 0, auto: false))
    }

    func pause(at date: Date = Date()) {
        guard var updated = run, updated.phase == .running else { return }
        now = date
        updated.stepAccumulated = Self.elapsed(of: updated, at: date)
        updated.stepResumedAt = nil
        updated.pausedAt = date
        updated.phase = .paused
        run = updated
        stopClock()
        persist()
        emit(.paused)
    }

    func resume(at date: Date = Date()) {
        guard var updated = run, updated.phase == .paused else { return }
        now = date
        if let pausedAt = updated.pausedAt {
            updated.totalPausedSeconds += max(0, date.timeIntervalSince(pausedAt))
        }
        updated.pausedAt = nil
        updated.stepResumedAt = date
        updated.phase = .running
        run = updated
        persist()
        startClock()
        emit(.resumed)
    }

    func completeCurrentStep(at date: Date = Date()) {
        guard var updated = run, updated.phase == .running,
              updated.steps.indices.contains(updated.currentIndex) else { return }
        now = date
        let step = updated.steps[updated.currentIndex]
        let elapsed = Self.elapsed(of: updated, at: date)
        updated.results.append(StepResult(
            stepID: step.id,
            title: step.title,
            plannedSeconds: step.durationSeconds,
            actualSeconds: Int(elapsed.rounded()),
            autoAdvanced: false
        ))

        if updated.currentIndex + 1 < updated.steps.count {
            updated.currentIndex += 1
            updated.stepAccumulated = 0
            updated.stepResumedAt = date
            updated.overtimeAnnounced = false
            run = updated
            persist()
            emit(.stepStarted(index: updated.currentIndex, auto: false))
        } else {
            finish(updated, endedAt: date)
        }
    }

    /// Returns to the previous step. Time spent on the current step is credited
    /// to the previous one, since the user was evidently still doing it.
    func undoLastStep(at date: Date = Date()) {
        guard var updated = run, updated.phase == .running, updated.currentIndex > 0,
              let last = updated.results.popLast() else { return }
        now = date
        let elapsed = Self.elapsed(of: updated, at: date)
        updated.currentIndex -= 1
        updated.stepAccumulated = Double(last.actualSeconds) + elapsed
        updated.stepResumedAt = date
        let duration = Double(updated.steps[updated.currentIndex].durationSeconds)
        updated.overtimeAnnounced = updated.stepAccumulated >= duration
        run = updated
        persist()
        emit(.steppedBack(index: updated.currentIndex))
    }

    func abandon(at date: Date = Date()) {
        guard var updated = run, updated.phase != .complete else { return }
        now = date
        if updated.phase == .paused, let pausedAt = updated.pausedAt {
            updated.totalPausedSeconds += max(0, date.timeIntervalSince(pausedAt))
            updated.pausedAt = nil
        }
        let partial = Self.elapsed(of: updated, at: date)
        updated.endedAt = date
        let result = Self.sessionResult(for: updated, completed: false, extraActiveSeconds: partial)
        run = nil
        stopClock()
        persist()
        emit(.abandoned(result))
    }

    func reset() {
        run = nil
        stopClock()
        persist()
        emit(.reset)
    }

    /// Advances the clock. Auto-next steps that have expired are completed, in
    /// a chain if the app was suspended across several of them.
    func tick(at date: Date = Date()) {
        now = date
        guard var updated = run, updated.phase == .running else { return }

        var lastAdvance: Event?
        var overtimeEvent: Event?

        while updated.steps.indices.contains(updated.currentIndex) {
            let step = updated.steps[updated.currentIndex]
            let elapsed = Self.elapsed(of: updated, at: date)
            guard elapsed >= Double(step.durationSeconds) else { break }

            if step.autoNext {
                let carry = elapsed - Double(step.durationSeconds)
                updated.results.append(StepResult(
                    stepID: step.id,
                    title: step.title,
                    plannedSeconds: step.durationSeconds,
                    actualSeconds: step.durationSeconds,
                    autoAdvanced: true
                ))

                if updated.currentIndex + 1 < updated.steps.count {
                    updated.currentIndex += 1
                    updated.stepAccumulated = carry
                    updated.stepResumedAt = date
                    updated.overtimeAnnounced = false
                    lastAdvance = .stepStarted(index: updated.currentIndex, auto: true)
                } else {
                    finish(updated, endedAt: date.addingTimeInterval(-carry))
                    return
                }
            } else {
                if !updated.overtimeAnnounced {
                    updated.overtimeAnnounced = true
                    overtimeEvent = .overtimeStarted(index: updated.currentIndex)
                }
                break
            }
        }

        if updated != run {
            run = updated
            persist()
        }
        if let lastAdvance { emit(lastAdvance) }
        if let overtimeEvent { emit(overtimeEvent) }
    }

    // MARK: - Notification planning

    /// Everything worth a local notification from `date` onward, assuming the
    /// user keeps up with the plan. Manual steps end the chain because their
    /// finish time is unknown; instead they get overtime nudges.
    func plannedAlerts(at date: Date) -> [PlannedAlert] {
        guard let run, run.phase == .running, run.steps.indices.contains(run.currentIndex) else { return [] }

        var alerts: [PlannedAlert] = []
        var index = run.currentIndex
        var end = date.addingTimeInterval(-Self.elapsed(of: run, at: date))
            .addingTimeInterval(TimeInterval(run.steps[index].durationSeconds))

        while run.steps.indices.contains(index) {
            let step = run.steps[index]
            let isLast = index == run.steps.count - 1

            if end > date {
                alerts.append(PlannedAlert(stepIndex: index, fireDate: end, kind: .stepEnd))
            }

            if isLast, step.autoNext {
                if end > date {
                    alerts.append(PlannedAlert(stepIndex: index, fireDate: end, kind: .completion))
                }
                break
            }

            if !step.autoNext {
                for minutes in Self.overtimeNudgeMinutes {
                    let fire = end.addingTimeInterval(TimeInterval(minutes * 60))
                    if fire > date {
                        alerts.append(PlannedAlert(stepIndex: index, fireDate: fire, kind: .overtime(minutes: minutes)))
                    }
                }
                break
            }

            index += 1
            if run.steps.indices.contains(index) {
                end = end.addingTimeInterval(TimeInterval(run.steps[index].durationSeconds))
            }
        }

        return alerts
    }

    // MARK: - Internals

    private static func elapsed(of run: RoutineRun, at date: Date) -> TimeInterval {
        guard run.phase != .complete else { return 0 }
        var elapsed = run.stepAccumulated
        if let resumedAt = run.stepResumedAt {
            elapsed += max(0, date.timeIntervalSince(resumedAt))
        }
        return elapsed
    }

    private static func sessionResult(for run: RoutineRun, completed: Bool, extraActiveSeconds: TimeInterval = 0) -> SessionResult {
        SessionResult(
            startedAt: run.startedAt,
            endedAt: run.endedAt ?? run.startedAt,
            plannedSeconds: run.plannedSeconds,
            activeSeconds: run.results.reduce(0) { $0 + $1.actualSeconds } + Int(extraActiveSeconds.rounded()),
            pausedSeconds: Int(run.totalPausedSeconds.rounded()),
            completed: completed,
            steps: run.results
        )
    }

    private func finish(_ finished: RoutineRun, endedAt: Date) {
        var updated = finished
        updated.phase = .complete
        updated.endedAt = endedAt
        updated.stepResumedAt = nil
        updated.stepAccumulated = 0
        updated.overtimeAnnounced = false
        run = updated
        stopClock()
        persist()
        emit(.completed(Self.sessionResult(for: updated, completed: true)))
    }

    private func persist() {
        store?.save(run)
    }

    private func emit(_ event: Event) {
        onEvent?(event)
    }

    private func startClock() {
        guard usesWallClock else { return }
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick(at: Date())
                guard self.isRunning else { return }

                // Sleep until just after the next whole second so the display never skips.
                let reference = Date().timeIntervalSinceReferenceDate
                let untilNextSecond = reference.rounded(.up) - reference
                try? await Task.sleep(for: .seconds(max(0.05, untilNextSecond + 0.01)))
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }
}
