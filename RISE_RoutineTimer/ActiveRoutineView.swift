//
//  ActiveRoutineView.swift
//  RISE_RoutineTimer
//
//  The running-timer screen.
//
//  The design is "silent until it matters": on a good morning the screen is
//  the step icon, its name, a rule, and the countdown — nothing else. It only
//  speaks when the *routine* is at risk, and step-level trouble is carried by
//  the colour of the fill rather than by a label.
//
//  Chrome lives in one place: a floating bar at the bottom, in the shape of
//  Arc's URL bar. A chevron on the left that raises the run sheet, the
//  projected finish in the middle, then notes (when the step has one) and
//  pause at the right edge, under the thumb. The bar's top edge fills
//  in proportion to the whole routine. That replaced a row of four chips and
//  a strip of step dots across the top, which with sixteen steps ran edge to
//  edge and left nothing for the eye to rest on.
//
//  Structure, and why it is this way:
//
//  * Static type lives inside `InvertingFillView` so it inverts across the
//    fill line. Every *control* lives in the sibling overlay instead, because
//    the fill builds its content twice and would otherwise give us two of
//    each button stacked on top of each other.
//  * The check and skip chips are the one exception, and only by half: their
//    *visuals* are drawn inside the fill, so the fill line crosses them the
//    way it crosses the type, while the overlay holds invisible hit targets
//    of the same size in the same slot.
//  * The bar is opaque white and floats above the fill. It has to be: it
//    sits at the bottom, which is inside the coloured region for most of a
//    step, and a grey-on-black progress edge would be fighting the indigo
//    behind it otherwise.
//  * The step name opens the notes sheet. It is drawn as plain text inside
//    the fill (so it still inverts) and the tap target is placed over it in
//    the overlay, using an anchor the content publishes.
//  * Auto-next is said once: the AUTO / MANUAL badge under the step name.
//    Both chips carry the same dashed border whatever the step.
//
//  Two progress indicators, on purpose: the rising fill is *this step*; the
//  bar's edge is *the whole routine*. They measure different things.
//
//  Everything here is snapped, not animated, exactly like the FLIP timer:
//  see the note in InvertingFillView about per-tick invalidation.
//

import SwiftUI

/// Which optional lines the running screen shows. Both default to on.
nonisolated enum ActiveScreenSettings {
    static let showStepTimesKey = "activeShowStepTimes"
    static let showNextStepKey = "activeShowNextStep"
}

/// Where the step name ended up, so the notes tap target can sit on top of it.
/// Where the AUTO / MANUAL badge landed, so its tap target can be placed
/// over it from the control layer. Same reason as `TitleBoundsKey`: the
/// badge is drawn inside the fill's content closure, which runs twice, so
/// the button itself must live outside it.
private struct BadgeBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct TitleBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct ActiveRoutineView: View {
    let engine: RoutineEngine
    let schedule: TargetSchedule
    let theme: FillTheme
    let onShowNotes: (_ editing: Bool) -> Void
    /// Called once the user has confirmed; this view owns the confirmation.
    let onEnd: () -> Void

    @State private var confirmingEnd = false
    @State private var confirmingSkip = false
    @State private var showingRunSheet = false
    /// A finger is down on the check mark. The chip is drawn inside the fill
    /// and its button lives in the overlay, so the press has to be carried
    /// across by hand for the drawn chip to answer it.
    @State private var checkPressed = false
    /// The bar's centre flips from "done at" to elapsed for a moment on tap.
    @State private var showingElapsed = false
    @State private var elapsedFlash: Task<Void, Never>?

    @AppStorage(ActiveScreenSettings.showStepTimesKey) private var showStepTimes = true
    @AppStorage(ActiveScreenSettings.showNextStepKey) private var showNextStep = true

    /// The slot the primary button occupies. Fixed, so a change of step never
    /// moves the type above it.
    private let buttonSlotHeight: CGFloat = 128
    private let checkDiameter: CGFloat = 104
    private let barHeight: CGFloat = 54
    private let barGap: CGFloat = 14
    private let progressEdgeHeight: CGFloat = 3

    /// Height of the "NEXT — ..." zone under the button; collapses to nothing
    /// when the setting is off. Both layers read this same value, so the
    /// button and its reserved slot stay aligned either way.
    private var nextZoneHeight: CGFloat { showNextStep ? 58 : 0 }

    /// Both layers ignore the safe area and re-apply it through this, so the
    /// reserved slots in the type layer and the real controls in the control
    /// layer are positioned by identical arithmetic.
    private func bottomInset(_ insets: EdgeInsets) -> CGFloat { max(insets.bottom, 16) + 4 }

    private var pace: StepPace { StepPace(overtimeSeconds: engine.overtimeSeconds) }
    private var hasNotes: Bool { engine.currentStep?.hasNotes == true }

    /// The night routine runs on a black page with white type; the fill
    /// still rises in the theme colour. Everything drawn on the page reads
    /// off `textColor`, so only the chips' ghost discs need to know.
    private var isDarkPage: Bool { engine.kind == .night }

    /// Overtime already means "this step is waiting on you", so there is
    /// nothing left to toggle — see `RoutineEngine.toggleAutoNextForCurrentStep`.
    private var canToggleAutoNext: Bool {
        engine.isRunning && !engine.isPaused && !engine.isOvertime
    }

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets

            ZStack {
                ZStack {
                    InvertingFillView(
                        fillColor: pace.fillColor(theme: theme),
                        fillFraction: engine.currentStepFillProgress,
                        pageColor: isDarkPage ? .black : .white,
                        pageTextColor: isDarkPage ? .white : .black
                    ) { textColor, onFill in
                        content(textColor: textColor, onFill: onFill, insets: insets)
                    }

                    controls(insets: insets)
                }
                .blur(radius: engine.isPaused ? 18 : 0)
                .scaleEffect(engine.isPaused ? 1.06 : 1)

                if engine.isPaused {
                    PauseOverlay(
                        engine: engine,
                        onResume: { engine.resume() },
                        onEnd: { confirmingEnd = true }
                    )
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.22), value: engine.isPaused)
            // The step name is the notes affordance. The tap target has to be
            // out here, not in the content closure, or there would be two.
            .overlayPreferenceValue(TitleBoundsKey.self) { anchor in
                if let anchor, hasNotes, !engine.isPaused {
                    GeometryReader { proxy in
                        let frame = proxy[anchor]
                        Button { onShowNotes(false) } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityLabel("Show notes for \(engine.currentStep?.title ?? "this step")")
                    }
                    .ignoresSafeArea()
                }
            }
            // The badge flips the step between auto and manual for this run.
            // Same placement trick as the title, and for the same reason.
            .overlayPreferenceValue(BadgeBoundsKey.self) { anchor in
                if let anchor, canToggleAutoNext {
                    GeometryReader { proxy in
                        let frame = proxy[anchor]
                        Button {
                            if engine.toggleAutoNextForCurrentStep() {
                                RoutineHaptics.shared.selectionChanged()
                            }
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // A 9pt capsule is a small target; give it the 44pt
                        // the finger expects without moving what is drawn.
                        .frame(width: max(frame.width, 88), height: max(frame.height, 44))
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityLabel(
                            engine.currentStep?.autoNext == false
                                ? "Manual step, waits for you"
                                : "Automatic step, advances on its own"
                        )
                        .accessibilityHint(
                            engine.currentStep?.autoNext == false
                                ? "Double tap to let this step advance on its own, just for this run"
                                : "Double tap to make this step wait for you, just for this run"
                        )
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .sheet(isPresented: $showingRunSheet) {
            RunSheetView(
                engine: engine,
                schedule: schedule,
                onShowNotes: { editing in afterSheetDismisses { onShowNotes(editing) } },
                onEnd: { afterSheetDismisses { confirmingEnd = true } }
            )
        }
        .receiptDialog(isPresented: $confirmingSkip, title: "Skip this step?") {
            ReceiptDialogAction.destructive("Skip it") {
                // Skipping the last step still finishes the routine.
                let finishing = engine.isOnLastStep
                RoutineHaptics.shared.stepSkipped()
                engine.skipCurrentStep()
                if finishing { RoutineHaptics.shared.routineComplete() }
            }
            if !engine.isOnLastStep {
                ReceiptDialogAction.quiet("Move to the end") {
                    RoutineHaptics.shared.stepSkipped()
                    engine.moveCurrentStepToEnd()
                }
            }
            ReceiptDialogAction.quiet("Cancel") {}
        }
        .receiptDialog(
            isPresented: $confirmingEnd,
            title: "End routine?",
            message: "This run will be saved as ended early, and you'll start from the first step next time.",
            confirmTitle: "End routine",
            cancelTitle: "Keep going",
            onConfirm: onEnd
        )
    }

    /// The run sheet dismisses itself before handing off, but the next
    /// presentation still needs the dismissal animation to finish first, or
    /// SwiftUI drops one of them.
    private func afterSheetDismisses(_ action: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            action()
        }
    }

    // MARK: - Type (inside the fill — no controls here)

    private func content(textColor: Color, onFill: Bool, insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            if showStepTimes {
                Text(stepTimeRangeText)
                    .font(analogFont(15))
                    .tracking(1.5)
                    .foregroundStyle(textColor.opacity(0.45))
                    .padding(.top, 14)
            }

            Spacer(minLength: 8)

            hero(textColor: textColor)

            Spacer(minLength: 8)

            // The chips are *drawn* here, in both layers, so the fill line
            // crosses them the way it crosses the type — half dark, half
            // white — instead of flipping them whole. Their hit targets live
            // in `controls`, in the same slot, because anything interactive
            // in this closure would exist twice.
            chipRow(textColor: textColor, onFill: onFill)
                .frame(height: buttonSlotHeight)

            if showNextStep {
                nextLabel(textColor: textColor)
                    .frame(height: nextZoneHeight)
            }

            // The floating bar's slot, reserved so the type above never
            // collides with it.
            Color.clear
                .frame(height: barGap + barHeight)
        }
        .padding(.top, insets.top + 8)
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
                .anchorPreference(key: TitleBoundsKey.self, value: .bounds) { $0 }

            // What kind of step this is — and, since it is tappable, what
            // you can make it instead. Still not a status message: overtime
            // is the fill colour's job, so this never changes on its own.
            // It changes only when you change it.
            Text(engine.currentStep?.autoNext == false ? "MANUAL" : "AUTO")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(textColor.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay {
                    Capsule().strokeBorder(textColor.opacity(0.35), lineWidth: 1)
                }
                .padding(.top, 12)
                .anchorPreference(key: BadgeBoundsKey.self, value: .bounds) { $0 }
                .accessibilityHidden(true)

            // The FLIP rule: a hard bar between the label and the digits.
            Rectangle()
                .fill(textColor)
                .frame(width: 132, height: 3)
                .padding(.vertical, 16)

            Text(displayTime)
                .font(digitFont(86))
                .monospacedDigit()
                .contentTransition(.identity)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityLabel(engine.isOvertime ? "\(displayTime) over" : "\(displayTime) remaining")

            // Said only when the routine as a whole is at risk. Nothing is
            // said about *this step* running over: the fill going amber and
            // then red already says it, and saying it twice was noise.
            if let alert = alertText {
                Text(alert)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(textColor.opacity(0.95))
                    .padding(.top, 14)
            }
        }
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
        let isRequired = engine.currentStep?.autoNext == false

        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Mirrors `chipRow` in `content` exactly: same slot, same sizes,
            // same spacing — these are the invisible buttons over the drawn
            // chips. The placeholder opposite skip keeps the check centred.
            HStack(spacing: 20) {
                Color.clear.frame(width: 46, height: 46)
                hitTarget(
                    diameter: checkDiameter,
                    label: isRequired ? "Complete step" : "Finish this step early",
                    onPress: { pressed in
                        checkPressed = pressed
                        if pressed { RoutineHaptics.shared.pressDown() }
                    }
                ) {
                    // The last step's chunk runs straight into the routine's
                    // flourish; see `RoutineHaptics`.
                    let finishing = engine.isOnLastStep
                    RoutineHaptics.shared.stepDone()
                    engine.completeCurrentStep()
                    if finishing { RoutineHaptics.shared.routineComplete() }
                }
                hitTarget(diameter: 46, label: "Skip or defer this step") {
                    confirmingSkip = true
                }
            }
            .frame(height: buttonSlotHeight)

            Color.clear.frame(height: nextZoneHeight)

            bottomBar
                .frame(height: barHeight)
                .padding(.top, barGap)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, bottomInset(insets))
    }

    /// An invisible button the size of a drawn chip.
    private func hitTarget(
        diameter: CGFloat,
        label: String,
        onPress: @escaping (Bool) -> Void = { _ in },
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Color.clear
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(PressReportingStyle(onPress: onPress))
        .accessibilityLabel(label)
    }

    // MARK: - Chips (drawn in the fill's layers)

    /// The check and skip chips, painted for one layer of the inverting
    /// fill: `textColor` is black on the page and white inside the fill, so
    /// the glyph, ring and ghost fill follow it and the mask does the rest.
    private func chipRow(textColor: Color, onFill: Bool) -> some View {
        HStack(spacing: 20) {
            Color.clear.frame(width: 46, height: 46)
            // Pressed in while a finger is on it. It snaps rather than eases
            // — nothing inside the fill animates — which suits a control
            // that answers with a click.
            chip("checkmark", diameter: checkDiameter, weight: .light, textColor: textColor, onFill: onFill)
                .scaleEffect(checkPressed ? 0.93 : 1)
            chip("forward.end", diameter: 46, weight: .regular, textColor: textColor, onFill: onFill)
        }
    }

    /// One quiet chip at one size, whatever the step. Both chips carry the
    /// same dashed border — the `AUTO` / `MANUAL` capsule under the step name
    /// already says which kind of step this is, and having the border say it
    /// again in a second visual language was a code to learn for nothing.
    private func chip(_ systemName: String, diameter: CGFloat, weight: Font.Weight, textColor: Color, onFill: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: diameter * 0.34, weight: weight))
            .foregroundStyle(textColor.opacity(onFill ? 0.92 : 0.6))
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(chipFill(onFill: onFill)))
            .overlay {
                Circle().strokeBorder(
                    textColor.opacity(onFill ? 0.7 : 0.28),
                    style: StrokeStyle(lineWidth: 2, dash: [4, 5])
                )
            }
            .shadow(color: .black.opacity(onFill || isDarkPage ? 0 : 0.1), radius: 10, y: 3)
    }

    /// On the page the chip is a soft white disc — solid read as stark
    /// against the saturated fill. Under the fill it is a ghost: a whisper of
    /// white, the same way the type below the line turns white. On the
    /// night's black page the disc is a ghost too — a 72% white disc under a
    /// white glyph would swallow it.
    private func chipFill(onFill: Bool) -> Color {
        Color.white.opacity(onFill ? 0.16 : (isDarkPage ? 0.12 : 0.72))
    }

    // MARK: - Bottom bar

    /// Arc's URL bar, repurposed: a chevron for everything else, the one
    /// number worth keeping in view (when you'll be done), and the one
    /// control that needs to be a single tap (pause). The top edge is the
    /// whole routine's progress.
    private var bottomBar: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.1))
                    Rectangle()
                        .fill(Color(hex: 0x111111))
                        .frame(width: geo.size.width * engine.routinePlanProgress)
                }
            }
            .frame(height: progressEdgeHeight)
            .accessibilityLabel("Routine \(Int(engine.routinePlanProgress * 100)) percent through")

            // Left to right: chevron · DONE AT · notes, pause. Pause sits at
            // the right edge, under the thumb of a right hand, because it is
            // the one control with time pressure.
            HStack(spacing: 0) {
                barButton("chevron.up", label: "Run details") { showingRunSheet = true }
                if hasNotes {
                    // Balances notes + pause (40 + 52 − 14) so the centre
                    // label stays centred.
                    Color.clear.frame(width: 26, height: barHeight - progressEdgeHeight)
                }

                Spacer(minLength: 0)

                Button(action: toggleElapsed) {
                    ZStack {
                        if showingElapsed {
                            barLabel("\(TimeFormatting.clockTime(from: engine.activeElapsedSeconds)) ELAPSED")
                                .transition(rollUp)
                        } else {
                            barLabel("DONE AT \(TimeFormatting.shortClockTime(from: engine.projectedEndDate).uppercased())")
                                .transition(rollUp)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.snappy(duration: 0.28), value: showingElapsed)
                .accessibilityLabel(showingElapsed ? "Elapsed" : "Projected finish")
                .accessibilityHint("Tap to switch")

                Spacer(minLength: 0)

                // Only when there is a note: the icon is the signal that this
                // step has one, as much as the way to open it.
                if hasNotes {
                    barButton("note.text", label: "Show this step's notes", width: 40) { onShowNotes(false) }
                        .padding(.trailing, -14)
                }
                barButton("pause.fill", label: "Pause routine") { engine.pause() }
            }
            .frame(height: barHeight - progressEdgeHeight)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
    }

    private func barButton(_ systemName: String, label: String, width: CGFloat = 52, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x111111).opacity(0.75))
                .frame(width: width, height: barHeight - progressEdgeHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func barLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.8)
            .monospacedDigit()
            .foregroundStyle(Color(hex: 0x111111).opacity(0.8))
            .lineLimit(1)
    }

    /// Old reading rolls up and out, new one rolls up and in — a ticker, so
    /// the swap reads as one thing turning over rather than two things
    /// crossfading on top of each other.
    private var rollUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    /// Swaps the bar's centre to elapsed time. Tapping again swaps it back
    /// straight away; left alone it reverts after a few seconds.
    private func toggleElapsed() {
        elapsedFlash?.cancel()
        if showingElapsed {
            showingElapsed = false
            return
        }
        showingElapsed = true
        elapsedFlash = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            showingElapsed = false
        }
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

    /// Nil on a good morning. Missing the finish-by target is the more useful
    /// thing to say, so it wins over raw drift when both are true.
    private var alertText: String? {
        if let spare = schedule.spareSeconds(projectedEnd: engine.projectedEndDate), spare < 0,
           let target = schedule.targetDate(on: engine.now) {
            return "WON'T MAKE \(TimeFormatting.shortClockTime(from: target).uppercased())"
        }
        let delta = engine.scheduleDeltaSeconds
        guard delta > RoutinePace.behindAlertSeconds else { return nil }
        return RoutinePace.label(deltaSeconds: delta)
    }
}

/// The check and skip hit targets are invisible, so there is nothing here to
/// scale; what they need is to *report* the press, so the chip drawn inside
/// the fill can answer it and the haptic can land with the finger.
private struct PressReportingStyle: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
    }
}
