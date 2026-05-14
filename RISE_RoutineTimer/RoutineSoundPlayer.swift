//
//  RoutineSoundPlayer.swift
//  RISE_RoutineTimer
//
//  Built-in system sounds for lightweight feedback while the app is open.
//

import AudioToolbox
import Foundation

enum RoutineSoundPlayer {
    // These are short built-in iOS system sound identifiers.
    private static let stepSound: SystemSoundID = 1104
    private static let completionSound: SystemSoundID = 1025

    static func playStepTransition(isEnabled: Bool) {
        guard isEnabled else {
            return
        }

        AudioServicesPlaySystemSound(stepSound)
    }

    static func playCompletion(isEnabled: Bool) {
        guard isEnabled else {
            return
        }

        AudioServicesPlaySystemSound(completionSound)
    }
}
