//
//  MorningChartsView.swift
//  RISE_RoutineTimer
//
//  The charting half of the History tab, matching MorningCheckin's
//  HistoryScreen: a rolling-baseline table, thirty days of snooze and
//  activation as bars, routine duration as a line, and the missed-day
//  counters. Each chart carries a dashed average rule, which is the thing
//  that actually answers "better or worse than usual".
//
//  Swift Charts rather than a hand-rolled plot: it gets the axes, scaling and
//  accessibility for free.
//

import Charts
import SwiftUI
import UIKit

struct MorningChartsView: View {
    let metrics: MorningMetrics
    var now: Date = Date()

    /// Newest-last, which is the order a time axis wants.
    private var window: [MorningRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        return metrics.records
            .filter { $0.day >= cutoff && $0.wakeAt != nil }
            .sorted { $0.day < $1.day }
    }

    private func series(_ metric: MorningMetrics.Metric) -> [(day: Date, value: Int)] {
        window.compactMap { record in
            metrics.value(metric, for: record).map { (record.day, $0) }
        }
    }

    var body: some View {
        Group {
            baselinesSection
            chartSection(
                title: "Snooze — 30 days",
                metric: .snooze,
                unit: "min past target",
                style: .bars
            )
            chartSection(
                title: "Activation — 30 days",
                metric: .activation,
                unit: "min to start",
                style: .bars
            )
            chartSection(
                title: "Routine length — 30 days",
                metric: .duration,
                unit: "min",
                style: .line
            )
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

                ForEach(MorningMetrics.Metric.allCases) { metric in
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
                    Text("Wake spread")
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
            Text("Spread is how much your wake time varies. A small spread means the habit is stable, whatever the average says.")
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

    // MARK: - Charts

    private func chartSection(
        title: String,
        metric: MorningMetrics.Metric,
        unit: String,
        style: MetricChart.Style
    ) -> some View {
        let points = series(metric).map { MetricChart.Point(day: $0.day, value: $0.value) }
        return Section {
            MetricChart(points: points, metric: metric, unit: unit, style: style)
        } header: {
            Text(title)
        } footer: {
            if metric == .snooze, points.count >= 2 {
                Text("Darker bars are mornings you were up on time.")
            }
        }
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

// MARK: - One scrubbable chart

/// Thirty days of one metric. Drag a finger across it and the line above the
/// plot reports the morning under it; lift, and it goes back to the average.
///
/// The readout is a fixed line *above* the plot rather than a callout riding
/// the finger: a callout is under your thumb exactly when you want to read
/// it, and one that flips sides near the edges makes the numbers jump. Its
/// values cut rather than roll, like every other number in the app, and
/// crossing onto a new day ticks the way the schedule tape does.
struct MetricChart: View {
    nonisolated struct Point: Equatable {
        let day: Date
        let value: Int
    }

    enum Style { case bars, line }

    let points: [Point]
    let metric: MorningMetrics.Metric
    let unit: String
    let style: Style

    /// Where the finger is on the time axis. Swift Charts clears it when the
    /// touch ends.
    @State private var touch: Date?

    private var average: Double {
        Double(points.reduce(0) { $0 + $1.value }) / Double(max(1, points.count))
    }

    private var selected: Point? {
        touch.flatMap { Self.nearest(to: $0, in: points) }
    }

    /// The logged morning closest to a moment on the axis. Missed days leave
    /// gaps, so the finger is rarely exactly on one; a tie goes to the
    /// earlier day.
    nonisolated static func nearest(to date: Date, in points: [Point]) -> Point? {
        points.min { a, b in
            // A bar is drawn across its whole day, so measure to the middle
            // of it — measuring to midnight hands the right-hand half of
            // every bar to the next morning.
            let da = abs(date.timeIntervalSince(a.day.addingTimeInterval(12 * 3600)))
            let db = abs(date.timeIntervalSince(b.day.addingTimeInterval(12 * 3600)))
            return da == db ? a.day < b.day : da < db
        }
    }

    var body: some View {
        if points.count < 2 {
            Text("Not enough data yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                readout
                chart
                    .frame(height: 150)
            }
            .padding(.vertical, 6)
            .onChange(of: selected) { old, new in
                guard let new, old != nil, old != new else { return }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    // MARK: Readout

    private var readout: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(selected.map { Self.dayFormatter.string(from: $0.day).uppercased() } ?? "30-DAY AVERAGE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(selected == nil ? .secondary : .primary)
            Spacer()
            Text(valueText(selected?.value ?? Int(average.rounded())))
                .font(analogFont(17))
                .monospacedDigit()
                .foregroundStyle(selected == nil ? .secondary : .primary)
        }
        .contentTransition(.identity)
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .combine)
    }

    private func valueText(_ minutes: Int) -> String {
        guard metric == .snooze else { return "\(minutes) MIN" }
        if minutes == 0 { return "ON TIME" }
        return minutes > 0 ? "+\(minutes) MIN" : "\(abs(minutes)) MIN EARLY"
    }

    // MARK: Plot

    private var chart: some View {
        Chart {
            ForEach(points, id: \.day) { point in
                if style == .bars {
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value(unit, point.value)
                    )
                    .foregroundStyle(barColor(point.value))
                    .opacity(selected == nil || selected == point ? 1 : 0.35)
                    .cornerRadius(2)
                } else {
                    LineMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value(unit, point.value)
                    )
                    .foregroundStyle(Color.primary)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value(unit, point.value)
                    )
                    .foregroundStyle(Color.primary)
                    .symbolSize(selected == point ? 70 : 18)
                }
            }

            RuleMark(y: .value("Average", average))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                // An explicit Color, not `.secondary`: a hierarchical
                // style on a mark falls back to the chart's accent.
                .foregroundStyle(Color.gray.opacity(0.7))
                .annotation(position: .top, alignment: .trailing) {
                    Text("avg \(Int(average.rounded()))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

            if let selected {
                RuleMark(x: .value("Day", selected.day, unit: .day))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .zIndex(-1)
            }
        }
        .chartXSelection(value: $touch)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .transaction { $0.animation = nil }
    }

    /// Snooze is the one chart where the value has a good/bad reading, so it
    /// is the only one that gets a colour ramp.
    private func barColor(_ value: Int) -> Color {
        guard metric == .snooze else { return Color.secondary }
        if value <= 0 { return Color.primary }
        if value <= 15 { return Color.secondary }
        return Color.secondary.opacity(0.4)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}
