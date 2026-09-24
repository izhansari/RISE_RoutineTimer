//
//  EveningView.swift
//  RISE_RoutineTimer
//
//  The Today tab after dark. From a time set in Settings (7pm by default)
//  until 4am, the morning's page gives way to this one, which answers the
//  only question worth asking in the evening: if I started the night
//  routine now, when would I be done?
//
//  The morning's page stays as it is. A morning run still in progress keeps
//  it; a night run in progress, or finished tonight, is shown here.
//
//  It is black, like the night timer, so the switch is felt before anything
//  is read. The colours are explicit (`Ink`) rather than semantic, and the
//  page asks for the dark colour scheme so the status bar and the tab bar
//  go dark with it — the app is otherwise light-only.
//

import SwiftData
import SwiftUI

/// The night page's palette: white on black.
private enum Ink {
    static let page = Color.black
    static let text = Color.white
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.35)
    static let hairline = Color.white.opacity(0.2)
}

struct EveningView: View {
    @Environment(RoutineEngine.self) private var engine
    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]
    @AppStorage(NightSettings.targetStartKey) private var goalMinutes = NightSettings.defaultTargetStartMinutes
    @AppStorage(FillTheme.storageKey) private var fillThemeRaw = FillTheme.default.rawValue

    /// Every saved step; this page uses the night's.
    let allSteps: [RoutineStep]
    let now: Date
    /// Switches the app to the Run tab.
    let onOpenRun: () -> Void
    /// The header's Routines button: opens the routine screen on NIGHT.
    let onOpenRoutines: () -> Void
    let onOpenHistory: () -> Void
    let onOpenSettings: () -> Void

    private var steps: [RoutineStep] { allSteps.routine(.night) }
    private var plannedSeconds: Int { steps.reduce(0) { $0 + $1.durationSeconds } }
    private var tint: Color { (FillTheme(rawValue: fillThemeRaw) ?? .default).color }

    private var isNightRunLive: Bool { engine.hasActiveRun && engine.kind == .night }

    /// Tonight's finished night run, if there is one.
    private var tonight: RoutineSession? {
        let evening = MorningRecord.nightDay(of: now)
        return sessions.first { $0.kind == .night && $0.completed && MorningRecord.nightDay(of: $0.startedAt) == evening }
    }

    private var outlook: NightOutlook {
        let usual = RoutineStats(sessions: sessions.results(of: .night))
        return NightOutlook(
            now: now,
            plannedSeconds: plannedSeconds,
            usualSeconds: usual.fullRuns.count >= 2 ? usual.averageActiveSeconds : nil,
            goalMinutes: goalMinutes
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 20)
            hero
            Spacer(minLength: 20)
            if !steps.isEmpty, !isNightRunLive, tonight == nil {
                stepStrip
                    .padding(.bottom, 18)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom) {
            cta
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
        .foregroundStyle(Ink.text)
        .background(Ink.page.ignoresSafeArea())
        .contentTransition(.identity)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "moon").font(.system(size: 14, weight: .semibold))
                    Text("TONIGHT").font(.system(size: 12, weight: .semibold)).tracking(2)
                }
                label("START BY \(clock(outlook.goal))")
            }
            Spacer(minLength: 4)
            HomeHeaderButtons(
                color: Ink.secondary,
                onRoutines: onOpenRoutines,
                onHistory: onOpenHistory,
                onSettings: onOpenSettings
            )
        }
        .padding(.top, 8)
    }

    // MARK: - The one answer

    @ViewBuilder
    private var hero: some View {
        if let done = tonight {
            block(
                label: "NIGHT ROUTINE DONE AT",
                value: clock(done.endedAt),
                lines: ["\(TimeFormatting.durationText(from: done.activeSeconds)), started \(clock(done.startedAt).lowercased())."]
            )
        } else if isNightRunLive {
            block(
                label: "ON PLAN, DONE BY",
                value: clock(engine.projectedEndDate),
                color: tint,
                lines: ["Step \(engine.currentIndex + 1) of \(engine.steps.count) · \(engine.currentStep?.title ?? "")"]
            )
        } else if steps.isEmpty {
            block(
                label: "NO NIGHT ROUTINE YET",
                value: "--:--",
                color: Ink.tertiary,
                lines: ["Add steps on the Run tab, under NIGHT."]
            )
        } else {
            let o = outlook
            block(
                label: "START NOW, DONE BY",
                value: clock(o.finishOnPlan),
                lines: [
                    "\(TimeFormatting.durationText(from: plannedSeconds)) · \(steps.count) step\(steps.count == 1 ? "" : "s").",
                    o.finishAsUsual.map { "At your usual pace, \(clock($0).lowercased())." },
                    goalLine(o),
                ].compactMap { $0 }
            )
        }
    }

    /// Where now sits against the start goal, in words.
    private func goalLine(_ o: NightOutlook) -> String {
        if o.minutesToGoal > 0 {
            let wait = o.minutesToGoal >= 60
                ? "\(o.minutesToGoal / 60) hr \(o.minutesToGoal % 60) min"
                : "\(o.minutesToGoal) min"
            let atGoal = clock(o.goal.addingTimeInterval(TimeInterval(plannedSeconds))).lowercased()
            return "Your goal is to start in \(wait), and be done by \(atGoal)."
        } else if o.minutesToGoal == 0 {
            return "It's your start time."
        } else {
            return "\(-o.minutesToGoal) min past your \(clock(o.goal).lowercased()) start goal."
        }
    }

    private func block(label: String, value: String, color: Color = Ink.text, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            self.label(label)
            Text(value)
                .font(digitFont(64))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 16))
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The night's steps as a row of their glyphs, so "7 steps" has a shape.
    private var stepStrip: some View {
        let shown = Array(steps.prefix(9))
        return VStack(alignment: .leading, spacing: 8) {
            label("THE ROUTINE")
            HStack(spacing: 6) {
                ForEach(shown, id: \.stepID) { step in
                    Text(step.icon.isEmpty ? "•" : step.icon)
                        .font(.system(size: 17))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
                }
                if steps.count > shown.count {
                    label("+\(steps.count - shown.count)")
                }
            }
        }
    }

    // MARK: - Button

    @ViewBuilder
    private var cta: some View {
        if isNightRunLive {
            button("BACK TO ROUTINE", icon: "timer", filled: false, action: onOpenRun)
        } else if tonight != nil {
            Text("NIGHT LOGGED")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else if !steps.isEmpty {
            button("START NIGHT ROUTINE", icon: "moon.fill", filled: true) {
                if engine.hasActiveRun { onOpenRun(); return }
                if engine.isComplete { engine.reset() }
                // The Run tab follows the run's kind when it starts.
                UserDefaults.standard.set(RoutineKind.night.rawValue, forKey: RoutineKind.selectionKey)
                engine.start(steps: steps.map(RunStep.init), kind: .night)
                onOpenRun()
            }
        }
    }

    private func button(_ title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(analogFont(20)).tracking(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(filled ? Ink.text : Color.clear)
            .foregroundStyle(filled ? Ink.page : Ink.text)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.hairline, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Text

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(Ink.secondary)
    }

    private func clock(_ date: Date) -> String {
        TimeFormatting.shortClockTime(from: date).uppercased()
    }
}
