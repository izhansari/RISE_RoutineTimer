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

    private enum ChartStyle { case bars, line }

    @ViewBuilder
    private func chartSection(
        title: String,
        metric: MorningMetrics.Metric,
        unit: String,
        style: ChartStyle
    ) -> some View {
        let points = series(metric)
        Section {
            if points.count < 2 {
                Text("Not enough data yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                let average = Double(points.reduce(0) { $0 + $1.value }) / Double(points.count)
                Chart {
                    ForEach(points, id: \.day) { point in
                        if style == .bars {
                            BarMark(
                                x: .value("Day", point.day, unit: .day),
                                y: .value(unit, point.value)
                            )
                            .foregroundStyle(barColor(metric: metric, value: point.value))
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
                            .symbolSize(18)
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
                }
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
                .frame(height: 150)
                .padding(.vertical, 6)
            }
        } header: {
            Text(title)
        } footer: {
            if metric == .snooze, points.count >= 2 {
                Text("Darker bars are mornings you were up on time.")
            }
        }
    }

    /// Snooze is the one chart where the value has a good/bad reading, so it
    /// is the only one that gets a colour ramp.
    private func barColor(metric: MorningMetrics.Metric, value: Int) -> Color {
        guard metric == .snooze else { return Color.secondary }
        if value <= 0 { return Color.primary }
        if value <= 15 { return Color.secondary }
        return Color.secondary.opacity(0.4)
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
