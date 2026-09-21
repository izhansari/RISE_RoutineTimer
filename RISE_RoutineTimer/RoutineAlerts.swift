//
//  RoutineAlerts.swift
//  RISE_RoutineTimer
//
//  In-app feedback for routine events: chimes that play even on silent,
//  spoken announcements, and haptics.
//
//  **None of the audio runs on the main thread.** It used to, and every tap
//  of the check mark paid for it: the handler blocked 22–33 ms in the steady
//  state and 265 ms on the first step of a run, so the press never released
//  cleanly and the step change stuttered. Measured, not guessed —
//  `AVAudioPlayer(contentsOf:)` 11–18 ms (80 ms cold), `AVAudioSession
//  .setActive` 73 ms, the first `speak` 110 ms, all of it inside
//  `engine.completeCurrentStep()`. A chime is not worth a dropped frame on
//  the one control this app asks you to press sixteen times a morning.
//
//  So the sound lives in `RoutineSound`, behind a serial queue: the tap
//  returns at once and the chime catches up a few milliseconds later, which
//  is inaudible. The haptics stay on the main thread on purpose — they have
//  to land with the finger, and they are already immediate.
//

import AVFoundation
import UIKit

final class RoutineAlerts {
    private let sound = RoutineSound()
    private let successHaptic = UINotificationFeedbackGenerator()

    /// - Parameter auto: the engine advanced by itself. Only then does the
    ///   phone buzz: a step you ticked off has already answered your finger
    ///   (`RoutineHaptics`), and a second, generic buzz on top of that one
    ///   turned a click into a rattle.
    func stepStarted(_ step: RunStep, isLast: Bool, auto: Bool, sounds: Bool, voice: Bool) {
        if auto { successHaptic.notificationOccurred(.success) }
        var line = "\(step.title). \(TimeFormatting.spokenDuration(from: step.durationSeconds))."
        if isLast { line += " Last step." }
        sound.play(chime: sounds ? "chime_step" : nil, say: voice ? line : nil)
    }

    func overtime(_ step: RunStep, sounds: Bool, voice: Bool) {
        successHaptic.notificationOccurred(.warning)
        sound.play(chime: sounds ? "chime_over" : nil,
                   say: voice ? "Time's up for \(step.title)." : nil,
                   speechDelay: sounds ? 0.5 : 0)
    }

    /// - Parameter byHand: the last step was ticked off, so the check mark has
    ///   already played the routine's flourish; an auto-advanced finish gets
    ///   the system success buzz instead.
    func completed(_ result: SessionResult, byHand: Bool, sounds: Bool, voice: Bool) {
        if !byHand { successHaptic.notificationOccurred(.success) }
        let line = "Routine complete in \(TimeFormatting.spokenDuration(from: result.activeSeconds))."
        sound.play(chime: sounds ? "chime_done" : nil,
                   say: voice ? line : nil,
                   speechDelay: sounds ? 0.9 : 0)
    }

    func stopSpeaking() {
        sound.stopSpeaking()
    }

    /// Builds the players and resolves the voice while nothing is waiting on
    /// them. Called when a run starts, so the first check mark of the morning
    /// does not pay the cold cost the rest of them avoid.
    func warmUp() {
        sound.warmUp()
    }
}

// MARK: - The sound, off the main thread

/// Every chime and every utterance, on one serial queue.
///
/// `@unchecked Sendable` because the state below is confined to `queue` by
/// discipline rather than by the compiler: nothing touches it anywhere else.
/// Keep it that way.
private final class RoutineSound: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.betternorms.rise.alerts", qos: .userInitiated)

    // MARK: Queue-confined state
    private var players: [String: AVAudioPlayer] = [:]
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionActive = false
    private var settleWork: DispatchWorkItem?
    /// Doubly optional: the outer nil means "not resolved yet", the inner
    /// means "this device offered none".
    private var resolvedVoice: AVSpeechSynthesisVoice??

    func play(chime: String?, say line: String?, speechDelay: TimeInterval? = nil) {
        guard chime != nil || line != nil else { return }
        // A chime and a voice together want the voice to wait for it.
        let delay = speechDelay ?? (chime != nil ? 0.45 : 0)
        queue.async { [self] in
            activateSession()
            if let chime { playNow(chime) }
            if let line { sayNow(line, delay: delay) }
            scheduleSettle()
        }
    }

    func stopSpeaking() {
        queue.async { [self] in synthesizer.stopSpeaking(at: .immediate) }
    }

    func warmUp() {
        queue.async { [self] in
            activateSession()
            for name in ["chime_step", "chime_over", "chime_done"] { _ = player(name) }
            _ = preferredVoice()
            scheduleSettle()
        }
    }

    // MARK: Players

    /// Built once and kept. A fresh `AVAudioPlayer` per chime re-read and
    /// re-decoded the file on every single step.
    private func player(_ resource: String) -> AVAudioPlayer? {
        if let existing = players[resource] { return existing }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav"),
              let made = try? AVAudioPlayer(contentsOf: url) else { return nil }
        made.prepareToPlay()
        players[resource] = made
        return made
    }

    private func playNow(_ resource: String) {
        guard let player = player(resource) else { return }
        player.currentTime = 0
        player.play()
    }

    private func sayNow(_ text: String, delay: TimeInterval) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice()
        utterance.preUtteranceDelay = delay
        synthesizer.speak(utterance)
    }

    /// `speechVoices()` is slow enough to be worth resolving once.
    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        if let resolvedVoice { return resolvedVoice }
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        let chosen = candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
        resolvedVoice = .some(chosen)
        return chosen
    }

    // MARK: Session

    /// `.playback` is what makes the chime audible with the ringer switched
    /// off. Ducking keeps a podcast or music going underneath.
    private func activateSession() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            sessionActive = true
        } catch {
            print("Audio session error: \(error)")
        }
    }

    /// Releases the session (and un-ducks other audio) once we have gone
    /// quiet, re-checking while anything is still sounding.
    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [self] in
            guard !synthesizer.isSpeaking, !players.values.contains(where: \.isPlaying) else {
                scheduleSettle()
                return
            }
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            sessionActive = false
        }
        settleWork = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
