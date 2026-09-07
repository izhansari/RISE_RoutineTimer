//
//  TodayView.swift
//  RISE_RoutineTimer
//
//  The landing screen, and the app's answer to "am I getting better or worse?"
//  Modelled on MorningCheckin's HomeScreen: the day's three moments on a
//  timeline, today's numbers next to a rolling baseline, the weekly budgets,
//  and one insight at a time.
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
    static let activation = Color(hex: 0x4A32DC)   // wake → routine start
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

    @Query private var logs: [MorningLog]
    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]

    @AppStorage(MorningSettings.targetWakeKey) private var targetWakeMinutes = MorningSettings.defaultTargetWakeMinutes
    @AppStorage(MorningSettings.snoozeBudgetKey) private var snoozeBudget = MorningSettings.defaultSnoozeBudget
    @AppStorage(MorningSettings.activationBudgetKey) private var activationBudget = MorningSettings.defaultActivationBudget
    @AppStorage("todayBaselinePeriod") private var baselineRaw = BaselinePeriod.sevenDay.rawValue
    @AppStorage(FillTheme.storageKey) private var fillThemeRaw = FillTheme.default.rawValue

    @State private var insightIndex = 0
    @State private var editingWake = false
    @State private var confirmingUndoWake = false

    /// Steps to hand the engine when the routine is started from here.
    let steps: [RoutineStep]
    /// Switches the app to the Run tab.
    let onStartRoutine: () -> Void

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

    private var today: MorningRecord {
        metrics.record(on: Date()) ?? MorningRecord(day: Calendar.current.startOfDay(for: Date()))
    }

    /// A run in progress hasn't been written to history yet, so the live start
    /// time has to come from the engine.
    private var effectiveStart: Date? {
        engine.routineStartDate ?? today.routineStartAt
    }

    // MARK: - Stage

    private enum Stage { case awake, start, running, complete }

    /// How long after the target wake time the live snooze counter keeps
    /// running before it gives up and shows nothing.
    private static let liveSnoozeWindow: TimeInterval = 6 * 60 * 60

    private var stage: Stage {
        if today.wakeAt == nil { return .awake }
        if engine.hasActiveRun { return .running }
        if today.routineEndAt == nil { return .start }
        return .complete
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                // One ticking clock drives every live value on the screen.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let now = context.date
                    VStack(spacing: 14) {
                        header
                        timelineCard(now: now)
                        performanceCard(now: now)
                        budgetCard(now: now)
                        insightCard(now: now)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editingWake) { wakeEditor }
            .receiptDialog(
                isPresented: $confirmingUndoWake,
                title: "Undo wake up?",
                message: "Today's wake time will be cleared. Your snooze and activation numbers for this morning go with it.",
                confirmTitle: "Undo it",
                cancelTitle: "Keep it",
                onConfirm: {
                    MorningLogStore(context: modelContext).setWake(nil, on: Date(), existing: logs)
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(greeting)
                .font(.system(size: 26, weight: .bold))
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("GOAL WAKE · \(clockOfDay(settings.targetWakeMinutes))")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timelineCard(now: Date) -> some View {
        if today.wakeAt != nil {
            Card {
                HStack {
                    CardLabel("TODAY")
                    Spacer()
                    Button("EDIT") { editingWake = true }
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
                DayTimeline(
                    goal: settings.targetWake(on: today.wakeAt ?? now),
                    wake: today.wakeAt,
                    start: effectiveStart,
                    end: today.routineEndAt,
                    now: now,
                    isRunning: engine.hasActiveRun,
                    routineColor: (FillTheme(rawValue: fillThemeRaw) ?? .default).color
                )
                .padding(.top, 14)
            }
        }
    }

    // MARK: - Performance

    private func performanceCard(now: Date) -> some View {
        Card {
            HStack {
                CardLabel("PERFORMANCE")
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(MorningMetrics.Metric.allCases) { metric in
                    PerformanceTile(
                        title: metric.title.uppercased(),
                        value: liveValueText(metric, now: now),
                        comparison: comparison(metric, now: now)
                    )
                }
            }
            .padding(.top, 12)

            ctaButton
                .padding(.top, 12)
        }
    }

    /// Live where it can be — the tile counts up while you are in the phase it
    /// measures, then freezes on the recorded value.
    private func liveValueText(_ metric: MorningMetrics.Metric, now: Date) -> String? {
        switch metric {
        case .snooze:
            guard let wake = today.wakeAt else {
                // Still in bed: count up from the target so the cost of lying
                // there is visible. Bounded, because an unlogged morning at
                // 9pm is not a fourteen-hour snooze — it is just unlogged.
                let target = settings.targetWake(on: now)
                let since = now.timeIntervalSince(target)
                guard since >= 0, since <= Self.liveSnoozeWindow else { return nil }
                return elapsed(since, signed: true)
            }
            return elapsed(wake.timeIntervalSince(settings.targetWake(on: wake)), signed: true)
        case .activation:
            guard let wake = today.wakeAt else { return nil }
            guard let start = effectiveStart else { return elapsed(now.timeIntervalSince(wake)) }
            return elapsed(start.timeIntervalSince(wake))
        case .duration:
            guard let start = effectiveStart else { return nil }
            guard let end = today.routineEndAt, !engine.hasActiveRun else {
                return elapsed(now.timeIntervalSince(start))
            }
            return elapsed(end.timeIntervalSince(start))
        }
    }

    /// Today's finished value against the chosen baseline.
    private func comparison(_ metric: MorningMetrics.Metric, now: Date) -> Comparison? {
        guard stage == .complete else { return nil }
        guard let todayValue = metrics.value(metric, for: today) else { return nil }
        let base: Int?
        switch baseline {
        case .last:
            base = metrics.previousValue(metric, now: now)
        case .sevenDay, .thirtyDay:
            base = metrics.rollingAverage(metric, days: baseline.days, now: now, excluding: now)
        }
        guard let base else { return nil }
        return Comparison(deltaMinutes: base - todayValue, metric: metric)
    }

    // MARK: - Budgets

    private func budgetCard(now: Date) -> some View {
        Card {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    CardLabel("WEEKLY BUDGET")
                    BudgetBar(
                        title: "Snooze",
                        used: metrics.weeklyBudgetUsed(.snooze, now: now),
                        budget: settings.snoozeBudgetMinutes
                    )
                    BudgetBar(
                        title: "Activation",
                        used: metrics.weeklyBudgetUsed(.activation, now: now),
                        budget: settings.activationBudgetMinutes
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    CardLabel("7-DAY")
                    MiniStat("Wake", metrics.averageWakeMinutes(days: 7, now: now).map(clockOfDay) ?? "—")
                    MiniStat("Activation", metrics.rollingAverage(.activation, days: 7, now: now).map { "\($0) min" } ?? "—")
                    MiniStat("Spread", metrics.wakeConsistencyMinutes(days: 7, now: now).map { "±\($0) min" } ?? "—")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Insight

    private func insightCard(now: Date) -> some View {
        let lines = metrics.insights(now: now)
        let index = lines.isEmpty ? 0 : insightIndex % lines.count
        return Button {
            insightIndex += 1
        } label: {
            Card {
                CardLabel("INSIGHT")
                Text(lines.isEmpty ? "Keep logging." : lines[index])
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                if lines.count > 1 {
                    Text("TAP FOR NEXT")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    @ViewBuilder
    private var ctaButton: some View {
        switch stage {
        case .awake:
            cta("I'M AWAKE", icon: "sun.horizon.fill") {
                MorningLogStore(context: modelContext).recordWake(at: Date(), existing: logs)
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
                            set: { MorningLogStore(context: modelContext).setWake($0, on: Date(), existing: logs) }
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

// MARK: - Comparison

private struct Comparison {
    /// Positive means today beat the baseline.
    let deltaMinutes: Int
    let metric: MorningMetrics.Metric

    var isBetter: Bool { deltaMinutes > 0 }
    var isNeutral: Bool { deltaMinutes == 0 }

    var text: String {
        if isNeutral { return "Same" }
        let word = metric == .duration ? (isBetter ? "faster" : "slower") : (isBetter ? "better" : "worse")
        return "\(abs(deltaMinutes))m \(word)"
    }

    var color: Color {
        if isNeutral { return .secondary }
        return isBetter ? MorningInk.good : MorningInk.bad
    }
}

// MARK: - Pieces

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

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

private struct MiniStat: View {
    let title: String
    let value: String
    init(_ title: String, _ value: String) { self.title = title; self.value = value }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(analogFont(16))
                .monospacedDigit()
        }
    }
}

private struct PerformanceTile: View {
    let title: String
    let value: String?
    let comparison: Comparison?

    var body: some View {
        VStack(spacing: 6) {
            Text(value ?? "--:--")
                .font(analogFont(21))
                .monospacedDigit()
                .contentTransition(.identity)
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(value == nil ? .tertiary : .secondary)

            Text(comparison?.text ?? " ")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(comparison?.color ?? .clear)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct BudgetBar: View {
    let title: String
    let used: Int
    let budget: Int

    private var remaining: Int { budget - used }
    private var fraction: Double { budget <= 0 ? 0 : min(Double(used) / Double(budget), 1) }
    private var isOver: Bool { remaining < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(isOver ? "\(abs(remaining)) over" : "\(used) min")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(isOver ? MorningInk.bad : .secondary)
            }
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(height: 12)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(isOver ? MorningInk.bad : Color.secondary)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) budget, \(used) of \(budget) minutes used")
    }
}

// MARK: - Day timeline

/// The four moments of the morning on a real time axis: the goal, when you
/// actually woke, when the routine started, and when it ended.
private struct DayTimeline: View {
    let goal: Date
    let wake: Date?
    let start: Date?
    let end: Date?
    let now: Date
    let isRunning: Bool
    /// The routine leg is drawn in whatever colour the timer fills with, so
    /// the two screens agree about what "the routine" looks like.
    let routineColor: Color

    private let trackY: CGFloat = 30
    private let padding: TimeInterval = 20 * 60

    /// The visible window, widened to at least 90 minutes so two events a
    /// minute apart don't sit on top of each other.
    private var bounds: (start: Date, end: Date) {
        var points = [goal, now]
        points.append(contentsOf: [wake, start, end].compactMap { $0 })
        var lower = (points.min() ?? goal).addingTimeInterval(-padding)
        var upper = (points.max() ?? goal).addingTimeInterval(padding)
        let minimum: TimeInterval = 90 * 60
        if upper.timeIntervalSince(lower) < minimum {
            let mid = lower.addingTimeInterval(upper.timeIntervalSince(lower) / 2)
            lower = mid.addingTimeInterval(-minimum / 2)
            upper = mid.addingTimeInterval(minimum / 2)
        }
        return (lower, upper)
    }

    private func fraction(_ date: Date) -> Double {
        let (lower, upper) = bounds
        let span = upper.timeIntervalSince(lower)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(lower) / span))
    }

    private var wakeColor: Color {
        guard let wake else { return .secondary }
        let late = wake.timeIntervalSince(goal) / 60
        if late <= 0 { return MorningInk.good }
        if late <= 30 { return MorningInk.warn }
        return MorningInk.bad
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .topLeading) {
                // Baseline
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                    .offset(y: trackY)

                // Hour ticks, thinned so the labels never run together.
                ForEach(hourTicks, id: \.self) { tick in
                    Text(TimeFormatting.shortClockTime(from: tick))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: fraction(tick) * width, y: 6)
                }

                // Activation segment, then the routine segment.
                if let wake, let start, start >= wake {
                    segment(from: wake, to: start, width: width, color: MorningInk.activation)
                }
                if let start {
                    segment(from: start, to: end ?? (isRunning ? now : start), width: width, color: routineColor)
                }

                dot(at: goal, width: width, color: .secondary, filled: false)
                if let wake { dot(at: wake, width: width, color: wakeColor, filled: true) }
                if let start { dot(at: start, width: width, color: MorningInk.activation, filled: true) }
                if let end { dot(at: end, width: width, color: routineColor, filled: true) }

                // Captions drop to a second row when they would collide, so a
                // wake and a finish minutes apart stay readable.
                ForEach(layoutCaptions(width: width)) { caption in
                    captionView(caption)
                }
            }
        }
        .frame(height: 104)
    }

    /// A time label under the axis, already positioned and row-assigned.
    struct TimelineCaption: Identifiable {
        let id: String
        let label: String
        let date: Date
        var x: CGFloat
        let color: Color
        var row: Int = 0
    }

    /// Minimum horizontal gap two captions need before one is pushed down.
    private static let captionGap: CGFloat = 74

    private func layoutCaptions(width: CGFloat) -> [TimelineCaption] {
        let inset: CGFloat = 26
        var items: [TimelineCaption] = [
            TimelineCaption(id: "goal", label: "GOAL", date: goal, x: fraction(goal) * width, color: .secondary)
        ]
        if let wake {
            items.append(TimelineCaption(id: "wake", label: "WOKE", date: wake, x: fraction(wake) * width, color: wakeColor))
        }
        if let end {
            items.append(TimelineCaption(id: "end", label: "DONE", date: end, x: fraction(end) * width, color: routineColor))
        }

        items.sort { $0.x < $1.x }

        // Clamp into the card, then push a label to the second row whenever it
        // lands closer than one label's width to the last one on the top row.
        var lastTopX: CGFloat?
        for index in items.indices {
            items[index].x = min(max(items[index].x, inset), width - inset)
            if let lastTopX, items[index].x - lastTopX < Self.captionGap {
                items[index].row = 1
            } else {
                items[index].row = 0
                lastTopX = items[index].x
            }
        }
        return items
    }

    private func captionView(_ caption: TimelineCaption) -> some View {
        VStack(spacing: 0) {
            Text(caption.label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            Text(TimeFormatting.shortClockTime(from: caption.date))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(caption.color)
        }
        .fixedSize()
        .position(x: caption.x, y: trackY + 26 + CGFloat(caption.row) * 30)
    }

    /// At most five labels, whatever the span — a fifteen-hour window would
    /// otherwise print every hour on top of itself.
    private var hourTicks: [Date] {
        let (lower, upper) = bounds
        let hours = upper.timeIntervalSince(lower) / 3600
        let step = max(1, Int((hours / 4).rounded(.up)))
        let calendar = Calendar.current

        var ticks: [Date] = []
        var cursor = calendar.date(bySetting: .minute, value: 0, of: lower) ?? lower
        if cursor < lower { cursor = cursor.addingTimeInterval(3600) }
        while cursor <= upper && ticks.count < 5 {
            let f = fraction(cursor)
            if f > 0.06 && f < 0.94 { ticks.append(cursor) }
            cursor = cursor.addingTimeInterval(TimeInterval(step) * 3600)
        }
        return ticks
    }

    private func segment(from: Date, to: Date, width: CGFloat, color: Color) -> some View {
        let x0 = fraction(from) * width
        let x1 = fraction(to) * width
        return Rectangle()
            .fill(color)
            .frame(width: max(2, x1 - x0), height: 2)
            .offset(x: x0, y: trackY - 0.5)
    }

    private func dot(at date: Date, width: CGFloat, color: Color, filled: Bool) -> some View {
        Circle()
            .fill(filled ? color : Color(.secondarySystemGroupedBackground))
            .overlay(Circle().strokeBorder(color, lineWidth: filled ? 0 : 1.5))
            .frame(width: filled ? 11 : 10, height: filled ? 11 : 10)
            .position(x: fraction(date) * width, y: trackY)
    }

}
