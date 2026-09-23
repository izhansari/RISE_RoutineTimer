//
//  RoutineHaptics.swift
//  RISE_RoutineTimer
//
//  What the check mark feels like.
//
//  Ticking off a step is the one thing this app asks you to do sixteen times a
//  morning, and it had no feel of its own: the only haptic was the system
//  "success" buzz that fired when the *next step started*, the same buzz an
//  auto-advanced step gives. So the press is now a small mechanical event —
//
//      finger lands   a light tick, and the chip presses in
//      finger lifts   ka-chunk: a sharp click, then a low soft thud 55 ms
//                     later, like a switch seating
//
//  — and the generic success buzz is kept for steps the app advances by
//  itself, where the phone is telling you something rather than answering
//  you. Finishing the routine gets a short rising flourish after the last
//  chunk.
//
//  Core Haptics, because `UIImpactFeedbackGenerator` can only play one
//  transient and the whole character of this is in the second beat. The
//  engine is haptics-only so it never touches the audio session the chimes
//  and voice depend on. Devices without a Taptic Engine (and the simulator)
//  fall back to plain impact generators.
//

import CoreHaptics
import UIKit

@MainActor
final class RoutineHaptics {
    static let shared = RoutineHaptics()

    /// One transient in a pattern.
    nonisolated struct Beat: Equatable {
        var time: TimeInterval
        var intensity: Float
        var sharpness: Float
    }

    // MARK: - The patterns (pure data, so they can be checked without a device)

    /// Click, then thud. The click is crisp and full; the thud is quieter and
    /// dull, which is what makes it read as weight rather than as a second tap.
    nonisolated static let stepDone: [Beat] = [
        Beat(time: 0, intensity: 1.0, sharpness: 0.85),
        Beat(time: 0.055, intensity: 0.65, sharpness: 0.15),
    ]

    /// Three beats, rising in strength and brightness, starting once the last
    /// step's chunk has finished.
    nonisolated static let routineComplete: [Beat] = [
        Beat(time: 0.20, intensity: 0.45, sharpness: 0.35),
        Beat(time: 0.31, intensity: 0.7, sharpness: 0.55),
        Beat(time: 0.45, intensity: 1.0, sharpness: 0.8),
    ]

    nonisolated static func pattern(_ beats: [Beat]) throws -> CHHapticPattern {
        try CHHapticPattern(
            events: beats.map { beat in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: beat.intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: beat.sharpness),
                    ],
                    relativeTime: beat.time
                )
            },
            parameters: []
        )
    }

    // MARK: - Playing

    private var engine: CHHapticEngine?
    /// `CHHapticEngine.start()` is not free, and it was being called on
    /// every press *and* every play. The engine tells us when it stops, so
    /// tracking it is enough.
    private var isRunning = false
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let pressGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let fallbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    /// The finger has landed on the check mark.
    func pressDown() {
        pressGenerator.impactOccurred(intensity: 0.7)
        // Warm the engine now so the chunk on release is not late.
        prepareEngine()
    }

    /// The step was ticked off.
    func stepDone() {
        play(Self.stepDone) { self.fallbackGenerator.impactOccurred(intensity: 1) }
    }

    /// A lighter acknowledgement, for skipping or deferring a step.
    func stepSkipped() {
        pressGenerator.impactOccurred(intensity: 1)
    }

    /// A setting was flipped by hand — the AUTO / MANUAL badge. The picker
    /// tick, which is what the schedule tape uses when the playhead crosses
    /// into a step: this is a selection changing, not an impact.
    func selectionChanged() {
        selectionGenerator.selectionChanged()
    }

    /// The last step was ticked off.
    func routineComplete() {
        play(Self.routineComplete) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func play(_ beats: [Beat], fallback: () -> Void) {
        guard supportsHaptics, let engine = prepareEngine() else {
            fallback()
            return
        }
        do {
            let player = try engine.makePlayer(with: Self.pattern(beats))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }

    @discardableResult
    private func prepareEngine() -> CHHapticEngine? {
        guard supportsHaptics else { return nil }
        if engine == nil {
            do {
                let made = try CHHapticEngine()
                // Never the audio session: the chimes and the voice own that.
                made.playsHapticsOnly = true
                made.isAutoShutdownEnabled = true
                // The system can stop or reset the engine at any time (a
                // call, backgrounding). Drop it and build a fresh one on the
                // next press rather than trying to revive this one.
                made.stoppedHandler = { [weak self] _ in
                    Task { @MainActor in
                        self?.engine = nil
                        self?.isRunning = false
                    }
                }
                made.resetHandler = { [weak self] in
                    Task { @MainActor in
                        self?.engine = nil
                        self?.isRunning = false
                    }
                }
                engine = made
            } catch {
                return nil
            }
        }
        guard !isRunning else { return engine }
        do {
            try engine?.start()
            isRunning = true
        } catch {
            engine = nil
            isRunning = false
        }
        return engine
    }
}
