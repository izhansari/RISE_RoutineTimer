//
//  TodayView.swift
//  RISE_RoutineTimer
//
//  The landing screen, and the app's answer to "am I getting better or worse?"
//  Descended from MorningCheckin's HomeScreen: this morning drawn against the
//  week (`MorningColumnsChart`), the one number that matters right now, the
//  finished morning against a rolling baseline, the weekly budgets, and one
//  insight at a time.
//
//  It also owns the wake CTA, because waking up happens before there is any
//  routine to be on the Run tab for.
//

import SwiftData
import SwiftUI

// MARK: - Palette
//
// Carried over from the web app so a morning reads the same in both places.

/// The timeline's inks, taken from the app's own palette rather than the web
/// app's. Waking is scored on the same green / amber / red the running timer
/// uses for pace, so "late" looks the same wherever it appears.
private enum MorningInk {
    static let good       = Color(hex: 0x0FA057)
    static let warn       = Color(hex: 0xE8890A)
    static let bad        = Color(hex: 0xDB2118)
}

/// Which baseline today is measured against.
private enum BaselinePeriod: String, CaseIterable, Identifiable {
    case last, sevenDay, thirtyDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last:      return "Last morning"
        case .sevenDay:  return "7-day avg"
        case .thirtyDay: return "30-day avg"
        }
    }

    var days: Int { self == .thirtyDay ? 30 : 7 }
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RoutineEngine.self) private var engine
    @Environment(AppNavigation.self) private var navigation

    @Query private var logs: [MorningLog]
    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]

    @AppStorage(MorningSettings.targetWakeKey) private var targetWakeMinutes = MorningSettings.defaultTargetWakeMinutes
    @AppStorage(MorningSettings.snoozeBudgetKey) private var snoozeBudget = MorningSettings.defaultSnoozeBudget
    @AppStorage(MorningSettings.activationBudgetKey) private var activationBudget = MorningSettings.defaultActivationBudget
    @AppStorage("todayBaselinePeriod") private var baselineRaw = BaselinePeriod.sevenDay.rawValue
    @AppStorage(FillTheme.storageKey) private var fillThemeRaw = FillTheme.default.rawValue

    @State private var editingWake = false
    @State private var confirmingUndoWake = false
    /// The day picked out on the week chart, if any.
    @State private var selectedDay: Int?

    /// Every saved step, both routines. Settings gets all of them; this
    /// screen, History and the engine (when started from here) mean the
    /// morning.
    let allSteps: [RoutineStep]
    /// Switches the app to the Run tab.
    let onStartRoutine: () -> Void

    /// Steps to hand the engine when the routine is started from here.
    private var steps: [RoutineStep] { allSteps.routine(.morning) }

    /// Today is the morning's screen. A night run in progress is still a
    /// run — the button has to lead back to it — but it is not the morning
    /// routine, so it never becomes today's routine start or its live column.
    private var isMorningRunLive: Bool { engine.hasActiveRun && engine.kind == .morning }

    @AppStorage(NightSettings.eveningStartKey) private var eveningStart = NightSettings.defaultEveningStartMinutes

    /// After the evening start (7pm unless changed) Today is the night's
    /// page — see `EveningView`. A morning run still going keeps the
    /// morning; a night run going shows the night whatever the hour.
    private func showsEvening(_ now: Date) -> Bool {
        if isMorningRunLive { return false }
        if engine.hasActiveRun && engine.kind == .night { return true }
        return NightSettings.isEvening(now, eveningStartMinutes: eveningStart)
    }

    private var settings: MorningSettings {
        MorningSettings(
            targetWakeMinutes: targetWakeMinutes,
            snoozeBudgetMinutes: snoozeBudget,
            activationBudgetMinutes: activationBudget
        )
    }

    private var metrics: MorningMetrics {
        MorningMetrics(records: MorningRecord.join(logs: logs, sessions: sessions), settings: settings)
    }

    private var baseline: BaselinePeriod {
        BaselinePeriod(rawValue: baselineRaw) ?? .sevenDay
    }

    private var tint: Color { (FillTheme(rawValue: fillThemeRaw) ?? .default).color }

    private var today: MorningRecord {
        metrics.record(on: Date()) ?? MorningRecord(day: Calendar.current.startOfDay(for: Date()))
    }

    /// A run in progress hasn't been written to history yet, so the live start
    /// time has to come from the engine.
    private var effectiveStart: Date? {
        (isMorningRunLive ? engine.routineStartDate : nil) ?? today.routineStartAt
    }

    // MARK: - Stage

    private enum Stage { case awake, start, running, complete }

    /// A live run wins over everything: with the timer going, the only useful
    /// button is the way back to it. It used to come second, so a routine
    /// started from the Run tab without a wake time left "I'm awake" up for
    /// the whole run. (A morning run logs its own wake time now — see
    /// `MorningSettings.impliedWake` — so this is for runs outside the
    /// morning, which don't.)
    private var stage: Stage {
        if engine.hasActiveRun { return .running }
        if today.wakeAt == nil { return .awake }
        if today.routineEndAt == nil { return .start }
        return .complete
    }

    // MARK: - Body

    /// One screen, no scrolling, the button always under the thumb: the week
    /// with today growing on the end of it, the one number that matters right
    /// now, and both weekly budgets with the one you are spending alive.
    ///
    /// It was a scrolling stack of four cards — timeline, performance tiles,
    /// budgets, insight — which meant the button moved depending on how far
    /// down you had scrolled, and this screen is used half-awake. The insight
    /// card moved to History, which is now a push from the week chart rather
    /// than a tab of its own.
    var body: some View {
        @Bindable var navigation = navigation

        return NavigationStack {
            // One ticking clock drives every live value on the screen.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                if showsEvening(now) {
                    EveningView(
                        allSteps: allSteps,
                        now: now,
                        onOpenRun: onStartRoutine,
                        onOpenRoutines: { navigation.openRoutines(kind: .night) },
                        onOpenHistory: { navigation.openHistory(kind: .night) },
                        onOpenSettings: { navigation.openSettings(kind: .night) }
                    )
                } else {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    // The chart takes the slack rather than a spacer: an
                    // empty third of the screen was doing nothing, and the
                    // mornings were squeezed into 124pt where a day's whole
                    // shape had to fit.
                    weekCard(now: now)
                        .padding(.top, 12)
                        .frame(maxHeight: .infinity)

                    stateBlock(now: now)
                        .padding(.top, 14)

                    budgetBlock(now: now)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaInset(edge: .bottom) {
                    ctaButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                }
                }
            }
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $navigation.showsHistory) {
                HistoryView(steps: allSteps, initialKind: navigation.historyKind)
            }
            .navigationDestination(isPresented: $navigation.showsSettings) {
                SettingsView(steps: allSteps, focus: navigation.settingsKind)
            }
            .sheet(isPresented: $editingWake) { wakeEditor }
            .receiptDialog(
                isPresented: $confirmingUndoWake,
                title: "Undo wake up?",
                message: "Today's wake time will be cleared. Your snooze and activation numbers for this morning go with it.",
                confirmTitle: "Undo it",
                cancelTitle: "Keep it",
                onConfirm: {
                    MorningLogStore(context: modelContext)
                        .setWake(nil, on: Date(), existing: logs, goalMinutes: settings.targetWakeMinutes)
                }
            )
        }
    }

    // MARK: - Header

    /// The greeting with the goal beneath it, and the three ways off this
    /// screen — Routines, History, Settings — in the corner. There is no tab
    /// bar; this header is the app's navigation.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting)
                    .font(.system(size: 25, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                CardLabel("GOAL \(clockOfDay(settings.targetWakeMinutes))")
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HomeHeaderButtons(
                onRoutines: { navigation.openRoutines(kind: .morning) },
                onHistory: { navigation.openHistory(kind: .morning) },
                onSettings: { navigation.openSettings(kind: .morning) }
            )
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    // MARK: - The week

    /// The last seven mornings with today's column still growing.
    ///
    /// Only the `ALL MORNINGS ›` button goes to History — the chart itself
    /// belongs to the chart: tap or drag across it to read any day of the
    /// week, exactly as on History's own. The whole card used to be one big
    /// button, so touching the chart at all threw you onto another screen.
    private func weekCard(now: Date) -> some View {
        let columns = weekColumns(now: now)
        let goal = settings.targetWakeMinutes
        let edge = liveEdge(nowMinutes: MorningColumn.minutes(now, into: Calendar.current.startOfDay(for: now)), now: now)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Swaps to the selected day's date. One line, always: left
                // to wrap it pushed the chart down, which is the whole thing
                // this layout is trying not to do.
                CardLabel(selectedHeader(columns: columns, now: now))
                    .lineLimit(1)
                    .fixedSize()
                Spacer()
                Button {
                    navigation.openHistory(kind: .morning)
                } label: {
                    HStack(spacing: 2) {
                        Text("ALL MORNINGS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.8)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All mornings")
                .accessibilityHint("Opens History")
            }
            GeometryReader { geo in
                MorningColumnsChart(
                    columns: columns,
                    scale: ClockScale(columns: columns, goal: goal, now: edge, keeping: columns.last),
                    tint: tint,
                    // The chart draws its day labels under the plot; this is
                    // the plot's share of whatever height the card got.
                    height: max(110, geo.size.height - MorningColumnsChart.labelStripHeight),
                    selection: $selectedDay,
                    liveIndex: columns.count - 1,
                    now: edge,
                    fadesHistory: true,
                    annotatesSelection: true,
                    label: { Calendar.current.isDate($0.day, inSameDayAs: now) ? "TODAY" : Self.dayNumber.string(from: $0.day) }
                )
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    /// The week's columns, with a run in progress patched in from the engine
    /// — it has not been written to history yet.
    private func weekColumns(now: Date) -> [MorningColumn] {
        let dayStart = Calendar.current.startOfDay(for: now)
        var columns = MorningColumn.window(
            records: metrics.records, endingOn: now, days: 8,
            currentGoal: settings.targetWakeMinutes
        )
        if isMorningRunLive, let start = engine.routineStartDate, var live = columns.last {
            live.start = MorningColumn.minutes(start, into: dayStart)
            live.end = nil
            live.pausedUntil = nil
            columns[columns.count - 1] = live
        }
        return columns
    }

    /// "THIS WEEK", or the day you have picked out.
    private func selectedHeader(columns: [MorningColumn], now: Date) -> String {
        guard let index = selectedDay, columns.indices.contains(index) else { return "THIS WEEK" }
        let column = columns[index]
        if Calendar.current.isDate(column.day, inSameDayAs: now) { return "TODAY" }
        // No "nothing logged" suffix — an empty column already says it, and
        // the extra words wrap.
        return Self.longDay.string(from: column.day).uppercased()
    }

    /// How far today's column has grown. Nil once the morning is over — and
    /// nil outside the morning altogether, so an unlogged day at 9pm does not
    /// draw a fourteen-hour snooze down the chart.
    private func liveEdge(nowMinutes: Int, now: Date) -> Int? {
        let window = MorningSettings.morningWindow
        switch stage {
        case .awake:
            let since = now.timeIntervalSince(settings.targetWake(on: now))
            return since >= 0 && since <= window ? nowMinutes : nil
        case .start:
            guard let wake = today.wakeAt, now.timeIntervalSince(wake) <= window else { return nil }
            return nowMinutes
        case .running:
            return nowMinutes
        case .complete:
            return nil
        }
    }

    // MARK: - Right now

    /// One number, for whichever part of the morning you are in — or, once it
    /// is over, the comparison, which becomes the headline in its place.
    @ViewBuilder
    private func stateBlock(now: Date) -> some View {
        switch stage {
        case .awake:
            let goal = settings.targetWake(on: now)
            let since = now.timeIntervalSince(goal)
            let usual = metrics.averageWakeMinutes(days: 7, now: now).map { "You're usually up by \(clockOfDay($0).lowercased())." }
            if since < 0 {
                bigNumber("UNTIL YOUR \(clockOfDay(settings.targetWakeMinutes)) GOAL", elapsed(-since), note: usual)
            } else if since <= MorningSettings.morningWindow {
                bigNumber("PAST YOUR \(clockOfDay(settings.targetWakeMinutes)) GOAL", "+" + elapsed(since), color: MorningInk.warn, note: usual)
            } else {
                bigNumber("NO WAKE TIME TODAY", "--:--", color: Color(.tertiaryLabel), note: nil)
            }
        case .start:
            let wake = today.wakeAt ?? now
            let usual = metrics.rollingAverage(.activation, days: 7, now: now, excluding: now)
                .map { "You usually start \($0) min after waking." }
            bigNumber("SINCE YOU WOKE AT \(TimeFormatting.shortClockTime(from: wake).uppercased())",
                      elapsed(now.timeIntervalSince(wake)), note: usual)
        case .running:
            // A night run is named for what it is: this card is the
            // morning's, and "into the routine" would read as the morning
            // routine going at 10pm.
            bigNumber(isMorningRunLive ? "INTO THE ROUTINE" : "INTO THE NIGHT ROUTINE",
                      elapsed(TimeInterval(engine.activeElapsedSeconds)),
                      color: tint,
                      note: "Done at \(TimeFormatting.shortClockTime(from: engine.projectedEndDate)) on plan.")
        case .complete:
            comparisonBlock(now: now)
        }
    }

    private func bigNumber(_ label: String, _ value: String, color: Color = .primary, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            CardLabel(label)
            Text(value)
                .font(digitFont(50))
                .monospacedDigit()
                .contentTransition(.identity)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let note {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The finished morning against a baseline you pick. Each figure carries
    /// a short rule under it — the app's own hard-rule idiom — coloured by
    /// whether the morning beat that baseline, with the baseline's own value
    /// spelled out underneath so the colour is never the only thing saying it.
    private func comparisonBlock(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel("THIS MORNING VS")
                Spacer()
                Menu {
                    Picker("Baseline", selection: $baselineRaw) {
                        ForEach(BaselinePeriod.allCases) { period in
                            Text(period.title).tag(period.rawValue)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(baseline.title)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(MorningMetrics.Metric.allCases) { metric in
                    StatCompare(
                        title: metric.title.uppercased(),
                        value: metrics.value(metric, for: today),
                        baseline: baselineValue(metric, now: now),
                        signed: metric == .snooze,
                        better: tint
                    )
                }
            }
        }
    }

    private func baselineValue(_ metric: MorningMetrics.Metric, now: Date) -> Int? {
        switch baseline {
        case .last:
            return metrics.previousValue(metric, now: now)
        case .sevenDay, .thirtyDay:
            return metrics.rollingAverage(metric, days: baseline.days, now: now, excluding: now)
        }
    }

    // MARK: - Budgets

    /// Both budgets, always on screen — and the one you are spending right
    /// now is visibly filling: its today-portion stands taller, breathes, and
    /// carries a NOW tag, while the other sits quiet.
    ///
    /// They used to be a card at the foot of a scrolling page, which meant
    /// you read them afterwards like a receipt. A budget is only worth
    /// showing while it can still change what you do: watching the snooze
    /// pips fill from bed is a reason to get up.
    private func budgetBlock(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            budgetRow(.snooze, title: "Snooze", budget: settings.snoozeBudgetMinutes, now: now)
            budgetRow(.activation, title: "Activation", budget: settings.activationBudgetMinutes, now: now)
        }
    }

    /// Which budget is being spent this second. Before the wake goal the
    /// answer is neither: you cannot be overspending snooze at 2 AM.
    private func liveBudget(now: Date) -> MorningMetrics.Metric? {
        switch stage {
        case .awake: return now >= settings.targetWake(on: now) ? .snooze : nil
        case .start: return .activation
        case .running, .complete: return nil
        }
    }

    /// Today's own contribution: live while you are spending it, the recorded
    /// figure once it is settled. Only overruns count, as the budget does.
    private func todaySpend(_ metric: MorningMetrics.Metric, now: Date) -> Int {
        switch metric {
        case .snooze:
            if let wake = today.wakeAt {
                return max(0, Int((wake.timeIntervalSince(settings.targetWake(on: wake)) / 60).rounded(.down)))
            }
            let since = now.timeIntervalSince(settings.targetWake(on: now))
            guard since >= 0, since <= MorningSettings.morningWindow else { return 0 }
            return Int(since / 60)
        case .activation:
            guard let wake = today.wakeAt else { return 0 }
            if let start = effectiveStart, start >= wake {
                return max(0, Int((start.timeIntervalSince(wake) / 60).rounded(.down)))
            }
            let since = now.timeIntervalSince(wake)
            guard since >= 0, since <= MorningSettings.morningWindow else { return 0 }
            return Int(since / 60)
        case .duration:
            return 0
        }
    }

    private func budgetRow(_ metric: MorningMetrics.Metric, title: String, budget: Int, now: Date) -> some View {
        BudgetPips(
            title: title,
            spentBefore: metrics.weeklyBudgetUsed(metric, now: now, excluding: now),
            today: todaySpend(metric, now: now),
            budget: budget,
            isLive: liveBudget(now: now) == metric,
            warn: MorningInk.warn,
            over: MorningInk.bad
        )
    }

    private static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    // MARK: - CTA

    @ViewBuilder
    private var ctaButton: some View {
        switch stage {
        case .awake:
            cta("I'M AWAKE", icon: "sun.horizon.fill") {
                MorningLogStore(context: modelContext)
                    .recordWake(at: Date(), existing: logs, goalMinutes: settings.targetWakeMinutes)
            }
        case .start:
            VStack(spacing: 10) {
                cta("START ROUTINE", icon: "play.fill") {
                    if engine.isComplete { engine.reset() }
                    engine.start(steps: steps.map(RunStep.init))
                    onStartRoutine()
                }

                // "I'm awake" is one tap and easy to hit by accident, and it
                // starts the clock on the whole morning's numbers.
                Button("UNDO WAKE UP") { confirmingUndoWake = true }
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        case .running:
            cta("BACK TO ROUTINE", icon: "timer", filled: false) { onStartRoutine() }
        case .complete:
            Text("MORNING LOGGED")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }

    private func cta(_ title: String, icon: String, filled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(analogFont(20)).tracking(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(filled ? Color.primary : Color.clear)
            .foregroundStyle(filled ? Color(.systemBackground) : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Wake editor

    private var wakeEditor: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Woke up at",
                        selection: Binding(
                            get: { today.wakeAt ?? Date() },
                            set: {
                                MorningLogStore(context: modelContext)
                                    .setWake($0, on: Date(), existing: logs, goalMinutes: settings.targetWakeMinutes)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                } footer: {
                    Text("Fix the time if you logged it late.")
                }
            }
            .navigationTitle("Today's Wake Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { editingWake = false }
                }
            }
        }
        .presentationDetents([.height(240)])
    }

    // MARK: - Formatting

    private func clockOfDay(_ minutesAfterMidnight: Int) -> String {
        let date = Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(TimeInterval(minutesAfterMidnight * 60))
        return TimeFormatting.shortClockTime(from: date).uppercased()
    }

    /// "42 MIN" under the hour, "1:20" beyond it — the resolution the
    /// finished figures and their comparison are both read at, and the one
    /// History reports. Seconds-precise, a morning that began five hours
    /// before the goal printed a nine-character `−5:09:57` that ran into the
    /// next column.
    nonisolated static func minuteText(_ minutes: Int, signed: Bool = false) -> String {
        let sign = signed && minutes > 0 ? "+" : (minutes < 0 ? "−" : "")
        let size = abs(minutes)
        return size < 60 ? "\(sign)\(size) MIN" : sign + "\(size / 60):" + String(format: "%02d", size % 60)
    }

    /// `MM:SS` under an hour, `H:MM:SS` beyond.
    private func elapsed(_ interval: TimeInterval, signed: Bool = false) -> String {
        let negative = interval < 0
        let total = Int(abs(interval).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let text = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
        return signed && negative ? "-\(text)" : text
    }
}

// MARK: - Pieces

private struct CardLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(.secondary)
    }
}

/// One finished figure against its baseline: the value, a short rule
/// coloured by whether the morning beat it, and the baseline spelled out —
/// so the colour is never the only thing carrying the comparison.
private struct StatCompare: View {
    let title: String
    let value: Int?
    let baseline: Int?
    let signed: Bool
    /// The user's theme colour, used for "you beat it".
    let better: Color

    /// A minute either way is rounding, not a difference.
    private static let tolerance = 1

    var body: some View {
        let delta = value.flatMap { v in baseline.map { v - $0 } }
        let same = delta.map { abs($0) <= Self.tolerance } ?? false
        let beat = (delta ?? 0) < 0
        let color: Color = delta == nil ? .secondary : same ? .secondary : (beat ? better : Color(hex: 0xE8890A))

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.tertiary)
            Text(value.map { TodayView.minuteText($0, signed: signed) } ?? "—")
                .font(analogFont(19))
                .monospacedDigit()
                .contentTransition(.identity)
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(color)
                .frame(width: 26, height: 2)
                .opacity(delta == nil ? 0.25 : 1)
            Text(caption(delta: delta, same: same, beat: beat))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func caption(delta: Int?, same: Bool, beat: Bool) -> String {
        guard let baseline else { return "no baseline yet" }
        let base = TodayView.minuteText(baseline, signed: signed)
        guard let delta, !same else { return "same as \(base)" }
        return "\(beat ? "−" : "+")\(abs(delta)) vs \(base)"
    }
}

/// A weekly budget as one pip per five minutes, in the app's own dot-matrix
/// register: the week already spent, then today's share, then what is left.
///
/// While the budget is genuinely being spent, today's pips breathe. Three
/// things about that were wrong first time and are worth not repeating:
///
///   * **Nothing moves.** Live pips used to be taller than the rest, and the
///     `repeatForever` animation — sitting inside a `TimelineView` that
///     rebuilds this whole screen every second — re-animated that height on
///     every rebuild. The pip visibly grew and shrank on its own.
///   * **The breath comes from a clock, not an implicit animation.** A
///     `repeatForever` inside a per-second rebuild is unpredictable; a value
///     derived from the current time is not, and it stops dead when it
///     should.
///   * **It only breathes when there is something to breathe about.** Before
///     the wake goal you are not spending snooze at all, and a blinking pip
///     on an empty budget is just a fault light.
///
/// Motion is never the only cue: the live row keeps full opacity, its label
/// lights up and it carries a NOW tag, so the state survives Reduce Motion,
/// colour-blindness and a glance from across the room.
private struct BudgetPips: View {
    let title: String
    let spentBefore: Int
    let today: Int
    let budget: Int
    let isLive: Bool
    let warn: Color
    let over: Color

    /// Minutes per pip. Five keeps a 60-minute budget to twelve marks, which
    /// fits the width and still reads as countable.
    private static let perPip = 5
    private static let pipHeight: CGFloat = 13

    private var spent: Int { spentBefore + today }
    private var isOver: Bool { spent > budget }
    /// Live *and* actually spending: today has put something on the board.
    private var isBreathing: Bool { isLive && today > 0 }

    private var color: Color {
        if isOver { return over }
        if budget > 0, spent > budget * 3 / 4 { return warn }
        return .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            // Paused unless something is being spent, so a still screen
            // costs nothing.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isBreathing)) { context in
                pips(breath: Self.breath(at: context.date))
            }
        }
        .opacity(isLive ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) budget")
        .accessibilityValue(
            "\(spent) of \(budget) minutes used"
            + (isOver ? ", \(spent - budget) over" : "")
            + (isBreathing ? ", being spent now" : "")
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(isLive ? color : .secondary)
            if isLive {
                Text("NOW")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(color, in: Capsule())
            }
            Spacer()
            // Spent *of* the budget, not "left" or "over". Either of those is
            // a distance from a number the row never printed, so 16 LEFT read
            // the same whether the week's allowance was 20 minutes or 90.
            Text("\(spent) OF \(budget) MIN")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(isOver ? color : .secondary)
                .contentTransition(.identity)
        }
    }

    private func pips(breath: Double) -> some View {
        let total = max(1, max(budget, spent) / Self.perPip)
        let filledBefore = spentBefore / Self.perPip
        let filledNow = spent / Self.perPip

        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                let isToday = index >= filledBefore && index < filledNow
                let isEdge = index == filledNow && isBreathing
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < filledBefore ? Color.primary.opacity(0.3)
                          : (isToday || isEdge) ? color
                          : Color.primary.opacity(0.07))
                    // Every pip is the same size, always. Only colour and
                    // opacity ever change.
                    .frame(height: Self.pipHeight)
                    .opacity(isEdge ? breath * 0.9 : isToday && isBreathing ? 0.55 + breath * 0.45 : 1)
            }
        }
    }

    /// A two-second breath, 0…1, straight off the clock.
    nonisolated static func breath(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
        return 0.5 - 0.5 * cos(phase * 2 * .pi)
    }
}
