//
//  PauseOverlay.swift
//  RISE_RoutineTimer
//
//  Pausing used to drop the user back to the Run tab's idle screen, which
//  reads as "the routine is over" — same list, same big primary button, tab
//  bar back. The run was still there, but nothing on screen said so.
//
//  So a pause now stays on the timer and dims it. The routine is visibly still
//  underneath, and the only prominent action is resuming.
//
//  Explicit black/white rather than `Color.primary`: this sits on a dark scrim
//  over a saturated fill, so it must not follow the system colour scheme.
//

import SwiftUI

struct PauseOverlay: View {
    let engine: RoutineEngine
    let onResume: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack {
            // The caller blurs the timer behind this, which is what stops
            // the step title and countdown reading as a second, offset copy
            // of the ones below. The scrim only has to buy contrast, so it
            // stays light enough for the fill colour to show through and the
            // routine to look paused rather than gone.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("PAUSED")
                    .font(analogFont(40))
                    .tracking(8)
                    .foregroundStyle(.white)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 110, height: 3)
                    .padding(.top, 16)

                Text((engine.currentStep?.title ?? "").uppercased())
                    .font(analogFont(22))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 18)
                    .padding(.horizontal, 32)

                Text(remainingText)
                    .font(digitFont(52))
                    .monospacedDigit()
                    .contentTransition(.identity)
                    .foregroundStyle(.white)
                    .padding(.top, 6)

                Text(contextText)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 12)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: onResume) {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill").font(.system(size: 16))
                            Text("RESUME").font(analogFont(20)).tracking(3)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                        .foregroundStyle(Color.black)
                    }
                    .buttonStyle(.plain)

                    Button(action: onEnd) {
                        Text("END ROUTINE")
                            .font(analogFont(15))
                            .tracking(2.5)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.45), lineWidth: 2))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 54)
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var remainingText: String {
        engine.isOvertime
            ? "+\(TimeFormatting.clockTime(from: engine.overtimeSeconds))"
            : TimeFormatting.clockTime(from: engine.secondsRemaining)
    }

    private var contextText: String {
        var parts = ["STEP \(engine.currentIndex + 1) OF \(engine.steps.count)"]
        if let start = engine.routineStartDate {
            parts.append("STARTED \(TimeFormatting.shortClockTime(from: start).uppercased())")
        }
        return parts.joined(separator: " · ")
    }
}
