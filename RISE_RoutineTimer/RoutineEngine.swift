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

/// Stores the in-flight run as a file in Application Support.
///
/// This used to live in `UserDefaults`, and an ended routine could come back
/// from the dead: `UserDefaults` hands writes to `cfprefsd`, which batches
/// them, so a removal could still be pending when the process died — and iOS
/// *will* kill a backgrounded app. The earlier save had committed, the removal
/// had not, and the next launch restored a run the user had already ended.
/// `synchronize()` did not reliably force it.
///
/// A run snapshot was never really a preference anyway. An atomic file write
/// lands immediately and deleting the file is immediate, so the whole class of
/// problem goes away.
final class FileRunStore: RunStore {
    private let url: URL
    /// Only used to migrate a run written by an older build, once.
    private let legacyDefaults: UserDefaults?
    private let legacyKey = "activeRoutineRun"

    /// Marks the one-time read of the old UserDefaults home as done.
    ///
    /// This has to be its own file rather than "the run file exists": ending a
    /// routine deletes the run file, and without a separate marker the next
    /// launch would fall back to UserDefaults and restore the very run that was
    /// just ended — which is exactly the bug this store was written to fix,
    /// reappearing through the migration path.
    private let migratedMarker: URL

    init(directory: URL? = nil, legacyDefaults: UserDefaults? = .standard) {
        let folder = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("active-run.json")
        migratedMarker = folder.appendingPathComponent("active-run.migrated")
        self.legacyDefaults = legacyDefaults
    }

    func load() -> RoutineRun? {
        if let data = try? Data(contentsOf: url) {
            return try? JSONDecoder().decode(RoutineRun.self, from: data)
        }
        guard !hasMigrated else { return nil }
        markMigrated()
        guard let legacyDefaults, let data = legacyDefaults.data(forKey: legacyKey) else { return nil }
        legacyDefaults.removeObject(forKey: legacyKey)
        return try? JSONDecoder().decode(RoutineRun.self, from: data)
    }

    func save(_ run: RoutineRun?) {
        // Any save means this store owns the run from here on.
        markMigrated()
        legacyDefaults?.removeObject(forKey: legacyKey)

        guard let run, let data = try? JSONEncoder().encode(run) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("Could not save the active run: \(error)")
        }
    }

    private var hasMigrated: Bool {
        FileManager.default.fileExists(atPath: migratedMarker.path)
    }

    private func markMigrated() {
        guard !hasMigrated else { return }
        try? Data().write(to: migratedMarker, options: .atomic)
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

    init(store: RunStore? = FileRunStore(), usesWallClock: Bool = true, now: Date = Date()) {
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

    /// Position in the routine by the *plan*: the planned time of every step
    /// finished so far, plus however much of the current step's planned time
    /// has passed, as a fraction of the whole.
    ///
    /// This is what a progress bar should mean. Finishing a step early jumps
    /// it forward to the step boundary; running over holds it there. The
    /// obvious alternative — `activeElapsedSeconds / plannedTotalSeconds` —
    /// barely moved when a five-minute step was done in one.
    var routinePlanProgress: Double {
        let total = plannedTotalSeconds
        guard total > 0 else { return 0 }
        let finished = results.reduce(0) { $0 + $1.plannedSeconds }
        let current = min(stepElapsed, Double(currentStep?.durationSeconds ?? 0))
        return min(1, (Double(finished) + current) / Double(total))
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

    /// Every step of the run laid out on the clock, as of `now`. Empty when
    /// there is no live run — a finished one has nothing left to project.
    var projectedSchedule: [ProjectedStep] {
        guard let run, run.phase != .complete else { return [] }
        return ProjectedStep.project(
            steps: run.steps,
            results: run.results,
            currentIndex: run.currentIndex,
            stepElapsed: stepElapsed,
            now: now
        )
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

    /// Skips the current step. It is still recorded — with `skipped` set and
    /// whatever time was already spent on it — so the session's actual time
    /// stays honest and the step simply contributes no sample to its own
    /// duration average.
    func skipCurrentStep(at date: Date = Date()) {
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
            autoAdvanced: false,
            skipped: true
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

    /// Defers the current step to the end of the run.
    ///
    /// Nothing is recorded: the step has not happened, and it will start from
    /// its full duration when it comes back around. The seconds already spent
    /// on it are dropped, which is the honest reading of "I'll do this later"
    /// and is usually only a few seconds anyway.
    ///
    /// A no-op on the last step, where there is no "end" to move to.
    func moveCurrentStepToEnd(at date: Date = Date()) {
        guard var updated = run, updated.phase == .running,
              updated.steps.indices.contains(updated.currentIndex),
              updated.currentIndex + 1 < updated.steps.count else { return }
        now = date
        let step = updated.steps.remove(at: updated.currentIndex)
        updated.steps.append(step)
        // currentIndex is unchanged and now points at what was the next step.
        updated.stepAccumulated = 0
        updated.stepResumedAt = date
        updated.overtimeAnnounced = false
        run = updated
        persist()
        emit(.stepStarted(index: updated.currentIndex, auto: false))
    }

    /// Applies a notes edit made during the run. The run holds frozen copies
    /// of the steps, so without this the screen would keep showing the old
    /// text until the next run started.
    func updateNotes(_ notes: String, forStepID stepID: UUID) {
        guard var updated = run,
              let index = updated.steps.firstIndex(where: { $0.id == stepID }),
              updated.steps[index].notes != notes else { return }
        updated.steps[index].notes = notes
        run = updated
        persist()
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
