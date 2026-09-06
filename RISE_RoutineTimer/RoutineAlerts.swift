//
//  RoutineAlerts.swift
//  RISE_RoutineTimer
//
//  In-app feedback for routine events: chimes that play even on silent,
//  spoken announcements, and haptics.
//

import AVFoundation
import UIKit

final class RoutineAlerts {
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var settleTask: Task<Void, Never>?
    private var sessionActive = false

    private let successHaptic = UINotificationFeedbackGenerator()
    private let impactHaptic = UIImpactFeedbackGenerator(style: .light)

    func stepStarted(_ step: RunStep, isLast: Bool, sounds: Bool, voice: Bool) {
        successHaptic.notificationOccurred(.success)
        if sounds { play("chime_step") }
        if voice {
            var line = "\(step.title). \(TimeFormatting.spokenDuration(from: step.durationSeconds))."
            if isLast { line += " Last step." }
            speak(line, delay: sounds ? 0.45 : 0)
        }
        settleAudioSession()
    }

    func overtime(_ step: RunStep, sounds: Bool, voice: Bool) {
        successHaptic.notificationOccurred(.warning)
        if sounds { play("chime_over") }
        if voice { speak("Time's up for \(step.title).", delay: sounds ? 0.5 : 0) }
        settleAudioSession()
    }

    func completed(_ result: SessionResult, sounds: Bool, voice: Bool) {
        successHaptic.notificationOccurred(.success)
        if sounds { play("chime_done") }
        if voice {
            speak("Routine complete in \(TimeFormatting.spokenDuration(from: result.activeSeconds)).", delay: sounds ? 0.9 : 0)
        }
        settleAudioSession()
    }

    func steppedBack() {
        impactHaptic.impactOccurred()
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Audio

    private func play(_ resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav") else { return }
        activateAudioSession()
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("Could not play \(resource): \(error)")
        }
    }

    private func speak(_ text: String, delay: TimeInterval) {
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice
        utterance.preUtteranceDelay = delay
        synthesizer.speak(utterance)
    }

    private static let preferredVoice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }()

    /// `.playback` is what makes the chime audible with the ringer switched off.
    /// Ducking keeps a podcast or music going underneath.
    private func activateAudioSession() {
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

    /// Releases the session (and un-ducks other audio) once we've gone quiet.
    private func settleAudioSession() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { return }
                let busy = self.synthesizer.isSpeaking || (self.player?.isPlaying ?? false)
                if !busy { break }
            }
            guard let self, !Task.isCancelled else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            self.sessionActive = false
        }
    }
}
