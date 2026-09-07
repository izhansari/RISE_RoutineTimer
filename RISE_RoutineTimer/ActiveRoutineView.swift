//
//  ActiveRoutineView.swift
//  RISE_RoutineTimer
//
//  The running-timer screen. Split out of RoutineTimerView, which had it as a
//  600-line blob of magic height fractions and hand-placed `.position()` calls.
//
//  Structure, and why it is this way:
//
//  * Static type lives inside `InvertingFillView` so it inverts across the
//    fill line. Every *control* lives in the sibling overlay instead, because
//    the fill builds its content twice and would otherwise give us two of
//    each button stacked on top of each other.
//  * Controls are white chips, which is what lets them sit outside the
//    inversion: a white circle reads against both the white page and the
//    coloured fill without any per-layer colour maths.
//  * The bottom cluster is a real centred HStack — undo, complete, notes —
//    with hidden placeholders holding the slots when undo or notes are
//    unavailable, so the big button never shifts sideways mid-routine.
//  * The old screen put four different numbers in the bottom-left corner at
//    four different opacities. They are now three aligned micro-stats, and
//    the ahead/behind signal is carried by the colour of the whole screen.
//
//  Everything here is snapped, not animated, exactly like the FLIP timer:
//  see the note in InvertingFillView about per-tick invalidation.
//

import SwiftUI

struct ActiveRoutineView: View {
    let engine: RoutineEngine
    let schedule: TargetSchedule
    let onShowNotes: () -> Void
    let onEnd: () -> Void

    private let checkDiameter: CGFloat = 128
    private let chipDiameter: CGFloat = 52
    private let topBarHeight: CGFloat = 44
    /// Fixed height of the "NEXT — ..." zone under the control cluster.
    private let nextZoneHeight: CGFloat = 58

    /// Both layers ignore the safe area and re-apply it through these, so the
    /// reserved slot in the type layer and the real button in the control
    /// layer are positioned by identical arithmetic. Getting this wrong is how
    /// the checkmark ended up sitting on top of the pace row.
    private func bottomInset(_ insets: EdgeInsets) -> CGFloat { max(insets.bottom, 16) + 8 }

    private var pace: RoutinePace { RoutinePace(deltaSeconds: engine.scheduleDeltaSeconds) }

    var body: some View {
        // The outer GeometryReader is the only thing that still sees the real
        // safe area, since the ZStack below deliberately ignores it.
        GeometryReader { geo in
            let insets = geo.safeAreaInsets

            ZStack {
                InvertingFillView(
                    fillColor: pace.fillColor,
                    fillFraction: engine.currentStepFillProgress
                ) { textColor in
                    content(textColor: textColor, insets: insets)
                }

                controls(insets: insets)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Type (inside the fill — no controls here)

    private func content(textColor: Color, insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            hero(textColor: textColor)

            Spacer(minLength: 8)

            paceRow(textColor: textColor)
                .padding(.bottom, 24)

            // The slot the control cluster occupies in the overlay. Reserved
            // here so the type above can never collide with it.
            Color.clear
                .frame(height: checkDiameter)

            nextLabel(textColor: textColor)
                .frame(height: nextZoneHeight)
        }
        .padding(.top, insets.top + topBarHeight)
        .padding(.bottom, bottomInset(insets))
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hero(textColor: Color) -> some View {
        VStack(spacing: 0) {
            if let icon = engine.currentStep?.icon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 34))
                    .padding(.bottom, 14)
            }

            Text((engine.currentStep?.title ?? "").uppercased())
                .font(analogFont(36))
                .tracking(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(textColor)
                .lineLimit(2)
                .minimumScaleFactor(0.5)

            // The FLIP rule: a hard bar between the label and the digits.
            Rectangle()
                .fill(textColor)
                .frame(width: 132, height: 3)
                .padding(.vertical, 18)

            Text(displayTime)
                .font(digitFont(86))
                .monospacedDigit()
                .contentTransition(.identity)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityLabel(engine.isOvertime ? "\(displayTime) over" : "\(displayTime) remaining")

            Text(stepTimeRangeText)
                .font(analogFont(17))
                .tracking(1.5)
                .foregroundStyle(textColor.opacity(0.55))
                .padding(.top, 10)
        }
    }

    /// Three aligned micro-stats replacing the old corner pile of numbers.
    private func paceRow(textColor: Color) -> some View {
        HStack(alignment: .top, spacing: 0) {
            microStat("PACE", pace.label(deltaSeconds: engine.scheduleDeltaSeconds), textColor)
            microStat("DONE", TimeFormatting.shortClockTime(from: engine.projectedEndDate).uppercased(), textColor)
            microStat("SPARE", spareValue, textColor)
        }
    }

    private func microStat(_ label: String, _ value: String, _ textColor: Color) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(textColor.opacity(0.4))
            Text(value)
                .font(analogFont(15))
                .tracking(1)
                .foregroundStyle(textColor.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func nextLabel(textColor: Color) -> some View {
        VStack(spacing: 4) {
            Text(engine.nextStep == nil ? "LAST STEP" : "NEXT")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(textColor.opacity(0.35))
            if let next = engine.nextStep {
                Text(next.title.uppercased())
                    .font(analogFont(18))
                    .tracking(2)
                    .foregroundStyle(textColor.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls (outside the fill — built once)

    private func controls(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            topBar
                .frame(height: topBarHeight)
                .padding(.top, insets.top + 4)

            Spacer(minLength: 0)

            // Mirrors the reserved slot in `content` exactly.
            bottomCluster
                .frame(height: checkDiameter)
                .padding(.bottom, nextZoneHeight + bottomInset(insets))
        }
        .padding(.horizontal, 20)
    }

    private var topBar: some View {
        HStack {
            chipButton("xmark", diameter: 38, label: "End routine", action: onEnd)

            Spacer()

            HStack(spacing: 7) {
                ForEach(engine.steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(dotColor(for: i))
                        .frame(width: i == engine.currentIndex ? 24 : 8, height: 5)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: engine.currentIndex)
            .accessibilityLabel("Step \(engine.currentIndex + 1) of \(engine.steps.count)")

            Spacer()

            chipButton("pause.fill", diameter: 38, label: "Pause routine") { engine.pause() }
        }
    }

    /// The dots sit above the fill line for almost the whole step, so they are
    /// drawn dark and only flip once the fill has actually reached them.
    private func dotColor(for index: Int) -> Color {
        let onFill = engine.currentStepFillProgress > 0.94
        let base = onFill ? Color.white : Color.black
        if index < engine.currentIndex { return base.opacity(0.45) }
        if index == engine.currentIndex { return base.opacity(0.9) }
        return base.opacity(0.18)
    }

    private var bottomCluster: some View {
        HStack(spacing: 20) {
            // Placeholders keep the checkmark centred when a side action is
            // unavailable, so the main target never moves under the thumb.
            Group {
                if engine.currentIndex > 0 {
                    chipButton("arrow.uturn.backward", diameter: chipDiameter, label: "Go back to previous step") {
                        engine.undoLastStep()
                    }
                } else {
                    placeholderChip
                }
            }

            Button {
                engine.completeCurrentStep()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: checkDiameter * 0.4, weight: .medium))
                    .foregroundStyle(Color(hex: 0x111111))
                    .frame(width: checkDiameter, height: checkDiameter)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Complete step")

            Group {
                if engine.currentStep?.hasNotes == true {
                    chipButton("note.text", diameter: chipDiameter, label: "Show notes", action: onShowNotes)
                } else {
                    placeholderChip
                }
            }
        }
    }

    private var placeholderChip: some View {
        Color.clear.frame(width: chipDiameter, height: chipDiameter)
    }

    private func chipButton(
        _ systemName: String,
        diameter: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.34, weight: .semibold))
                .foregroundStyle(Color(hex: 0x111111).opacity(0.75))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.white))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Text

    private var displayTime: String {
        engine.isOvertime
            ? "+\(TimeFormatting.clockTime(from: engine.overtimeSeconds))"
            : TimeFormatting.clockTime(from: engine.secondsRemaining)
    }

    private var stepTimeRangeText: String {
        let start = TimeFormatting.shortClockTime(from: engine.stepStartDate)
        let end = TimeFormatting.shortClockTime(from: engine.stepEndDate)
        return "\(start) – \(end)".uppercased()
    }

    private var spareValue: String {
        guard let spare = schedule.spareSeconds(projectedEnd: engine.projectedEndDate) else { return "—" }
        if abs(spare) < 30 { return "ON TARGET" }
        return "\(TimeFormatting.clockTime(from: spare))\(spare > 0 ? "" : " OVER")"
    }
}

/// The one place motion is allowed on this screen: a press response on the
/// controls. Everything else snaps, so the digits can never crossfade.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
