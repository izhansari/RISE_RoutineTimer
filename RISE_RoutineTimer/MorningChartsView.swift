//
//  MorningChartsView.swift
//  RISE_RoutineTimer
//
//  The accountability half of the History tab: the mornings chart, the
//  rolling-baseline table and the missed-day counters.
//
//  The chart is `MorningColumnsSection` — fourteen upright morning marks on
//  one clock (see `MorningColumns.swift`). It replaced three separate 30-day
//  charts, one per metric. Those could each say whether a number was going
//  up, and between them could not say what goes with what, because the three
//  never shared a day: "on the mornings I'm up earlier, do I start sooner?"
//  had no answer anywhere in the app.
//

import SwiftUI

struct MorningChartsView: View {
    let metrics: MorningMetrics
    var now: Date = Date()
    /// Opens the run that began at this moment (a session's identity).
    var onOpenRun: (Date) -> Void = { _ in }

    private var kind: RoutineKind { metrics.kind }

    var body: some View {
        Group {
            MorningColumnsSection(metrics: metrics, now: now, onOpenRun: onOpenRun)
            baselinesSection
            missedSection
        }
    }

    // MARK: - Rolling baselines

    private var baselinesSection: some View {
        Section {
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("METRIC").gridColumnAlignment(.leading)
                    Text("7-DAY").gridColumnAlignment(.trailing)
                    Text("30-DAY").gridColumnAlignment(.trailing)
                }
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

                // The night has no activation row: you were already up.
                ForEach(metrics.metrics) { metric in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text(metric.title)
                            .font(.subheadline)
                            .gridColumnAlignment(.leading)
                        baselineValue(metrics.rollingAverage(metric, days: 7, now: now), metric: metric)
                        baselineValue(metrics.rollingAverage(metric, days: 30, now: now), metric: metric)
                    }
                }

                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text(kind == .night ? "Start spread" : "Wake spread")
                        .font(.subheadline)
                        .gridColumnAlignment(.leading)
                    spreadValue(metrics.wakeConsistencyMinutes(days: 7, now: now))
                    spreadValue(metrics.wakeConsistencyMinutes(days: 30, now: now))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Rolling baselines")
        } footer: {
            Text(kind == .night
                 ? "Snooze is how late the routine began against your night goal. Spread is how much that start time varies — a small spread means the habit is stable, whatever the average says."
                 : "Spread is how much your wake time varies. A small spread means the habit is stable, whatever the average says.")
        }
    }

    private func baselineValue(_ value: Int?, metric: MorningMetrics.Metric) -> some View {
        Text(value.map { metric == .snooze ? signed($0) : "\($0) min" } ?? "—")
            .font(analogFont(17))
            .monospacedDigit()
            .gridColumnAlignment(.trailing)
    }

    private func spreadValue(_ value: Int?) -> some View {
        Text(value.map { "±\($0) min" } ?? "—")
            .font(analogFont(17))
            .monospacedDigit()
            .gridColumnAlignment(.trailing)
    }

    private func signed(_ minutes: Int) -> String {
        minutes > 0 ? "+\(minutes) min" : "\(minutes) min"
    }

    // MARK: - Missed days

    private var missedSection: some View {
        let missed = metrics.missedDays(now: now)
        return Section {
            HStack {
                missedTile("THIS WEEK", missed.week)
                missedTile("THIS MONTH", missed.month)
                missedTile("ALL TIME", missed.allTime)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Missed days")
        } footer: {
            Text("Days since your first log with nothing recorded. Today is never counted.")
        }
    }

    private func missedTile(_ label: String, _ count: Int) -> some View {
        VStack(spacing: 5) {
            Text("\(count)")
                .font(analogFont(30))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The mornings chart

/// The window the readout averages over when no day is selected. It is not
/// the page: the chart pages by fortnight, but "how am I doing lately" is a
/// question about the last week or month, whichever fortnight is showing.
nonisolated enum HistoryAveragePeriod: String, CaseIterable, Identifiable {
    case all, week, month

    var id: String { rawValue }
    static let storageKey = "historyAveragePeriod"

    var label: String {
        switch self {
        case .all: return "ALL"
        case .week: return "7 DAYS"
        case .month: return "30 DAYS"
        }
    }

    /// Nil means every record.
    var days: Int? {
        switch self {
        case .all: return nil
        case .week: return 7
        case .month: return 30
        }
    }
}

/// Fourteen mornings at a time, newest on the right. Tap a column or slide
/// across them and the box above reports that morning; with nothing selected
/// it reports the average over all mornings, or the last 7 or 30 days. ‹ ›
/// page back through older fortnights — past about three weeks the columns
/// are too thin to read, so the chart pages rather than squeezes.
struct MorningColumnsSection: View {
    let metrics: MorningMetrics
    var now: Date = Date()
    let onOpenRun: (Date) -> Void

    @AppStorage(FillTheme.storageKey) private var fillThemeRaw = FillTheme.default.rawValue
    @AppStorage(HistoryAveragePeriod.storageKey) private var periodRaw = HistoryAveragePeriod.all.rawValue
    /// 0 is the fortnight ending today; 1 the one before it.
    @State private var page = 0
    @State private var selected: Int?

    static let daysPerPage = 14

    private var period: HistoryAveragePeriod { HistoryAveragePeriod(rawValue: periodRaw) ?? .all }

    /// Averages over the chosen window, whichever fortnight is on screen.
    private var windowAverages: MorningColumnAverages {
        let calendar = metrics.calendar
        let cutoff = period.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now)) }
        let records = metrics.records.filter { record in cutoff.map { record.day >= $0 } ?? true }
        return MorningColumnAverages(records.map { MorningColumn(record: $0, currentGoal: metrics.settings.targetWakeMinutes) })
    }

    private var tint: Color { (FillTheme(rawValue: fillThemeRaw) ?? .default).color }
    private var kind: RoutineKind { metrics.kind }

    private var lastDay: Date {
        metrics.calendar.date(byAdding: .day, value: -page * Self.daysPerPage, to: now) ?? now
    }

    private var columns: [MorningColumn] {
        MorningColumn.window(
            records: metrics.records, endingOn: lastDay, days: Self.daysPerPage,
            currentGoal: metrics.settings.targetWakeMinutes, calendar: metrics.calendar
        )
    }

    /// There is an older page while anything was logged before this one.
    private var hasOlder: Bool {
        guard let first = columns.first?.day else { return false }
        return metrics.records.contains { $0.hasAnything && $0.day < first }
    }

    var body: some View {
        let columns = columns
        let goal = metrics.settings.targetWakeMinutes
        let scale = ClockScale(columns: columns, goal: goal)

        Section {
            VStack(alignment: .leading, spacing: 14) {
                readout(columns)
                MorningColumnsChart(
                    columns: columns, scale: scale, tint: tint,
                    selection: $selected,
                    kind: kind,
                    label: { Self.dayNumber.string(from: $0.day) }
                )
                MorningColumnsLegend(tint: tint, kind: kind)
            }
            .padding(.vertical, 8)
        } header: {
            // No "Mornings" / "Nights" here: the switch at the top of the
            // page already says which. Just the fortnight and its pager.
            HStack {
                Spacer()
                pager(columns)
            }
        } footer: {
            Text(kind == .night
                 ? "The clock runs down the page, so earlier is higher. The dotted line is how late you started against your goal, the cap is when you started, the box is the routine. An empty column is a missed night."
                 : "The clock runs down the page, so earlier is higher. A cap is when you woke, the thin line is how long until you started, the box is the routine. An empty column is a missed day.")
        }
    }

    // MARK: Readout

    private func readout(_ columns: [MorningColumn]) -> some View {
        let column = selected.flatMap { columns.indices.contains($0) ? columns[$0] : nil }
        let averages = windowAverages

        return VStack(alignment: .leading, spacing: 10) {
            // A fixed height whatever sits at the right — the period switch
            // with nothing selected, OPEN RUN › with a day — so selecting a
            // day never moves the chart beneath.
            HStack {
                Text(title(column, averages))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if let start = column?.sessionStart {
                    Button { onOpenRun(start) } label: {
                        Text("OPEN RUN ›")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } else if column == nil {
                    periodSwitch
                }
            }
            .frame(height: 24)
            HStack(alignment: .top, spacing: 18) {
                // At night the cap *is* the start, so there is no gap to report.
                stat(kind == .night ? "Started" : "Woke", (column == nil ? averages.wake : column?.wake).map(MorningColumnsChart.clockText) ?? "—")
                if kind == .morning {
                    stat("To start", (column == nil ? averages.lag : column?.lag).map(Self.span) ?? "—")
                }
                stat("Routine", (column == nil ? averages.routine : column?.routineMinutes).map { "\($0) MIN" } ?? "—", color: tint)
            }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(column == nil ? 0.14 : 1), lineWidth: column == nil ? 1 : 1.5))
        .contentTransition(.identity)
        .transaction { $0.animation = nil }
    }

    private func title(_ column: MorningColumn?, _ averages: MorningColumnAverages) -> String {
        if let column {
            let day = Self.longDay.string(from: column.day).uppercased()
            return column.hasAnything ? day : "\(day) · NOTHING LOGGED"
        }
        // The pills beside it finish the sentence: AVERAGE OF · ALL,
        // AVERAGE OF · 7 DAYS. Spelling the window out here as well ran the
        // row past the card's edge and truncated both halves.
        return averages.count == 0 ? "NOTHING LOGGED" : "AVERAGE OF"
    }

    /// ALL | 7 DAYS | 30 DAYS, in the same small-caps register as the title.
    private var periodSwitch: some View {
        HStack(spacing: 4) {
            ForEach(HistoryAveragePeriod.allCases) { option in
                let isOn = option == period
                Button { periodRaw = option.rawValue } label: {
                    Text(option.label)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary.opacity(0.55))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background {
                            if isOn {
                                Capsule().fill(Color.primary)
                            } else {
                                Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func stat(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(analogFont(21))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: Paging

    private func pager(_ columns: [MorningColumn]) -> some View {
        HStack(spacing: 2) {
            pageButton("chevron.left", label: "Earlier two weeks", enabled: hasOlder) { page += 1 }
            if let first = columns.first?.day, let last = columns.last?.day {
                Text("\(Self.shortDay.string(from: first)) – \(Self.shortDay.string(from: last))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .textCase(nil)
            }
            pageButton("chevron.right", label: "Later two weeks", enabled: page > 0) { page -= 1 }
        }
    }

    private func pageButton(_ systemName: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            selected = nil
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Formatting

    nonisolated private static func span(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60):" + String(format: "%02d", minutes % 60) : "\(minutes) MIN"
    }

    private static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}
