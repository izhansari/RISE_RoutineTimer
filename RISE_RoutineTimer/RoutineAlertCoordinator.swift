//
//  RoutineAlertCoordinator.swift
//  RISE_RoutineTimer
//
//  Listens to engine events and turns them into sounds, speech, haptics and
//  background notifications. Lives for the whole app so a run restored at
//  launch is covered before any view appears.
//

import Foundation

final class RoutineAlertCoordinator {
    static let soundsKey = "routineSoundsEnabled"
    static let voiceKey = "routineVoiceEnabled"

    private let engine: RoutineEngine
    private let alerts = RoutineAlerts()
    private let liveActivity = RoutineLiveActivityController()
    private let recordSession: (SessionResult) -> Void
    /// Called with the run's start time, from whichever door it was started:
    /// the Today tab, the Run tab or the Start intent.
    private let runStarted: (Date) -> Void

    init(
        engine: RoutineEngine,
        runStarted: @escaping (Date) -> Void = { _ in },
        recordSession: @escaping (SessionResult) -> Void
    ) {
        self.engine = engine
        self.runStarted = runStarted
        self.recordSession = recordSession
        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
        // A run restored at launch needs its activity back (or a stale one
        // from a finished run taken down) before any event fires.
        liveActivity.sync(with: engine)
    }

    func applicationDidBecomeActive() {
        engine.tick()
        RoutineNotificationManager.clearDelivered()
        // The engine may have caught up across several steps while the app
        // was suspended; the Lock Screen is only as current as this call.
        liveActivity.sync(with: engine)
    }

    private var soundsEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.soundsKey) as? Bool ?? true
    }

    private var voiceEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.voiceKey) as? Bool ?? true
    }

    private func handle(_ event: RoutineEngine.Event) {
        // Every event changes something the Lock Screen shows, or ends it.
        liveActivity.sync(with: engine)

        switch event {
        case .started:
            // Build the players and resolve the voice now, so the first
            // check mark of the morning is as cheap as the rest.
            alerts.warmUp()
            runStarted(engine.routineStartDate ?? Date())
        case .resumed:
            syncNotifications()
        case .paused, .reset:
            RoutineNotificationManager.cancelRunAlerts()
            alerts.stopSpeaking()
        case .stepStarted(let index, let auto):
            if engine.steps.indices.contains(index) {
                let isLast = index == engine.steps.count - 1
                alerts.stepStarted(engine.steps[index], isLast: isLast, auto: auto, sounds: soundsEnabled, voice: voiceEnabled)
            }
            syncNotifications()
        case .overtimeStarted(let index):
            if engine.steps.indices.contains(index) {
                alerts.overtime(engine.steps[index], sounds: soundsEnabled, voice: voiceEnabled)
            }
        case .autoNextChanged:
            // The whole shape of the plan changed: an auto chain is
            // scheduled whole, and a manual step gets overtime nudges
            // instead of a next-step end. Re-ask the engine.
            syncNotifications()
        case .completed(let result):
            RoutineNotificationManager.cancelRunAlerts()
            let byHand = result.steps.last?.autoAdvanced == false
            alerts.completed(result, byHand: byHand, sounds: soundsEnabled, voice: voiceEnabled)
            recordSession(result)
        case .abandoned(let result):
            RoutineNotificationManager.cancelRunAlerts()
            alerts.stopSpeaking()
            recordSession(result)
        }
    }

    private func syncNotifications() {
        let now = Date()
        RoutineNotificationManager.schedule(engine.plannedAlerts(at: now), steps: engine.steps, now: now)
    }
}
