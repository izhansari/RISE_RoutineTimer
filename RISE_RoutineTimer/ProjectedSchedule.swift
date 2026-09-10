//
//  ProjectedSchedule.swift
//  RISE_RoutineTimer
//
//  Where every step of the run sits on the clock: what time it started (or
//  will start), and what time it ends (or is projected to). This is what the
//  schedule tape in the run sheet is drawn from, and it answers the only
//  question anyone asks mid-routine — "when am I free?"
//
//  Pure, so it is unit tested. The past is reconstructed *backwards* from the
//  current step's start rather than forwards from `run.startedAt`: pauses and
//  deferred steps make the forward walk drift, and the one moment that has to
//  be exactly right is now.
//

import Foundation

nonisolated struct ProjectedStep: Identifiable, Equatable {
    enum State: Equatable { case done, current, upcoming }

    var id: UUID
    var index: Int
    var title: String
    var icon: String
    /// What the step was given, which is not always what it took.
    var plannedSeconds: Int
    var autoNext: Bool
    var start: Date
    var end: Date
    var state: State

    /// The span this step actually occupies on the tape: its real duration
    /// once finished, its planned duration before that.
    var seconds: Int { max(1, Int(end.timeIntervalSince(start).rounded())) }
}

extension ProjectedStep {
    /// Lays the whole run out on the clock, as of `now`.
    ///
    /// - Finished steps are walked backwards from the current step's start
    ///   using what they really took, so the tape lines up with now.
    /// - The current step ends at its planned end, or at `now` if it has
    ///   already run over — the same clamp `remainingPlannedSeconds` applies,
    ///   so the last step's end always equals `projectedEndDate`.
    /// - Later steps stack by their planned durations.
    static func project(
        steps: [RunStep],
        results: [StepResult],
        currentIndex: Int,
        stepElapsed: TimeInterval,
        now: Date
    ) -> [ProjectedStep] {
        guard !steps.isEmpty, steps.indices.contains(currentIndex) else { return [] }

        var out = [ProjectedStep?](repeating: nil, count: steps.count)

        let currentStart = now.addingTimeInterval(-max(0, stepElapsed))
        let plannedEnd = currentStart.addingTimeInterval(TimeInterval(steps[currentIndex].durationSeconds))
        out[currentIndex] = ProjectedStep(
            steps[currentIndex], index: currentIndex,
            start: currentStart, end: max(plannedEnd, now), state: .current
        )

        // Backwards through what already happened.
        var edge = currentStart
        for i in stride(from: currentIndex - 1, through: 0, by: -1) {
            let step = steps[i]
            // Matched by id, not position: deferring a step moves it to the
            // end of the run and records no result, so the two arrays are not
            // guaranteed to line up.
            let took = results.first { $0.stepID == step.id }?.actualSeconds ?? step.durationSeconds
            let start = edge.addingTimeInterval(-TimeInterval(max(1, took)))
            out[i] = ProjectedStep(step, index: i, start: start, end: edge, state: .done)
            edge = start
        }

        // Forwards through what is left.
        edge = out[currentIndex]!.end
        for i in (currentIndex + 1)..<steps.count {
            let step = steps[i]
            let end = edge.addingTimeInterval(TimeInterval(step.durationSeconds))
            out[i] = ProjectedStep(step, index: i, start: edge, end: end, state: .upcoming)
            edge = end
        }

        return out.compactMap { $0 }
    }

    private init(_ step: RunStep, index: Int, start: Date, end: Date, state: State) {
        self.init(
            id: step.id,
            index: index,
            title: step.title,
            icon: step.icon,
            plannedSeconds: step.durationSeconds,
            autoNext: step.autoNext,
            start: start,
            end: end,
            state: state
        )
    }
}
