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

    init(engine: RoutineEngine) {
        self.engine = engine
        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    func applicationDidBecomeActive() {
        engine.tick()
        RoutineNotificationManager.clearDelivered()
    }

    private var soundsEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.soundsKey) as? Bool ?? true
    }

    private var voiceEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.voiceKey) as? Bool ?? true
    }

    private func handle(_ event: RoutineEngine.Event) {
        switch event {
        case .started:
            break
        case .resumed:
            syncNotifications()
        case .paused, .reset:
            RoutineNotificationManager.cancelAll()
            alerts.stopSpeaking()
        case .stepStarted(let index, _):
            if engine.steps.indices.contains(index) {
                let isLast = index == engine.steps.count - 1
                alerts.stepStarted(engine.steps[index], isLast: isLast, sounds: soundsEnabled, voice: voiceEnabled)
            }
            syncNotifications()
        case .steppedBack:
            alerts.steppedBack()
            syncNotifications()
        case .overtimeStarted(let index):
            if engine.steps.indices.contains(index) {
                alerts.overtime(engine.steps[index], sounds: soundsEnabled, voice: voiceEnabled)
            }
        case .completed(let result):
            RoutineNotificationManager.cancelAll()
            alerts.completed(result, sounds: soundsEnabled, voice: voiceEnabled)
        case .abandoned:
            RoutineNotificationManager.cancelAll()
            alerts.stopSpeaking()
        }
    }

    private func syncNotifications() {
        let now = Date()
        RoutineNotificationManager.schedule(engine.plannedAlerts(at: now), steps: engine.steps, now: now)
    }
}
