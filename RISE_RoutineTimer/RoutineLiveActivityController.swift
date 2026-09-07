//
//  RoutineLiveActivityController.swift
//  RISE_RoutineTimer
//
//  Keeps the Live Activity in step with the engine: one activity while a run
//  exists, none otherwise. Driven from `RoutineAlertCoordinator`, which
//  already sees every engine event, and from the app becoming active, which
//  is the moment a restored run can catch up.
//
//  The content state is built synchronously on the main actor from the
//  engine and handed to the async ActivityKit calls, so the engine is never
//  read from another actor.
//

import ActivityKit
import Foundation

@MainActor
final class RoutineLiveActivityController {
    private var activity: Activity<RoutineActivityAttributes>?

    /// Reconciles the activity with the engine's current state. Safe to call
    /// often; a no-op when Live Activities are switched off in Settings.
    func sync(with engine: RoutineEngine) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard engine.hasActiveRun, let state = Self.state(from: engine) else {
            Task { await endAll() }
            return
        }

        Task { await upsert(state) }
    }

    private func upsert(_ state: RoutineActivityAttributes.ContentState) async {
        // Adopt an activity left over from a previous launch rather than
        // stacking a second one on the Lock Screen.
        if activity == nil {
            activity = Activity<RoutineActivityAttributes>.activities.first
        }

        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            await activity.update(content)
            return
        }

        do {
            activity = try Activity.request(
                attributes: RoutineActivityAttributes(routineName: "Morning Routine"),
                content: content,
                pushType: nil
            )
        } catch {
            print("Could not start the Live Activity: \(error)")
        }
    }

    private func endAll() async {
        for stale in Activity<RoutineActivityAttributes>.activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }

    private static func state(from engine: RoutineEngine) -> RoutineActivityAttributes.ContentState? {
        guard let step = engine.currentStep else { return nil }
        let theme = UserDefaults.standard.string(forKey: FillTheme.storageKey) ?? FillTheme.default.rawValue
        return RoutineActivityAttributes.ContentState(
            stepTitle: step.title,
            stepIcon: step.icon,
            stepIndex: engine.currentIndex + 1,
            stepCount: engine.steps.count,
            stepStart: engine.stepStartDate,
            stepEnd: engine.stepEndDate,
            autoNext: step.autoNext,
            nextTitle: engine.nextStep?.title,
            projectedEnd: engine.projectedEndDate,
            planProgress: engine.routinePlanProgress,
            isPaused: engine.isPaused,
            pausedRemainingSeconds: engine.secondsRemaining,
            theme: theme
        )
    }
}
