//
//  StepHistoryView.swift
//  RISE_RoutineTimer
//
//  One step over time, pushed from a step's name in the session summary.
//
//  Laid out as answers, most-asked first:
//  1. How long does it take me, and is my plan right?  → TYPICAL | VS PLAN,
//     with a one-sentence verdict that also says which way it's trending.
//  2. What does every run look like?                   → bars against the
//     plan line and the usual band.
//  3. The details worth a glance                        → best, slowest, where
//     it starts, share of the routine, how often it's finished, how often
//     it's on plan.
//  4. What should I change?                             → the suggestion, when
//     the evidence supports one.
//  5. The raw record                                    → recent runs.
//
//  The maths is `StepReport`.
//

import Charts
import SwiftData
import SwiftUI

struct StepHistoryRequest: Hashable, Identifiable {
    let stepID: UUID
    /// The name at the time of the run — used if the step has since been deleted.
    let title: String
    let plannedSeconds: Int

    var id: UUID { stepID }
}

struct StepHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]
    @Query private var routineSteps: [RoutineStep]
    @AppStorage(FillTheme.storageKey) private var fillThemeRaw = FillTheme.default.rawValue

    let request: StepHistoryRequest

    private static let overColor = Color(hex: 0xE8890A)
    private var tint: Color { (FillTheme(rawValue: fillThemeRaw) ?? .default).color }

    private var liveStep: RoutineStep? { routineSteps.first { $0.stepID == request.stepID } }
    private var plannedSeconds: Int { liveStep?.durationSeconds ?? request.plannedSeconds }
    private var title: String { liveStep?.title ?? request.title }

    var body: some View {
        let results = sessions.map(\.result)
        let report = StepReport(stepID: request.stepID, plannedSeconds: plannedSeconds, sessions: results)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(report)
                    .padding(.top, 6)

                hero(report)
                    .padding(.top, 18)

                if report.runs.isEmpty {
                    Text("No finished runs of this step yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 22)
                } else {
                    sectionLabel("Every run")
                        .padding(.top, 24)
                    chart(report)
                        .frame(height: 176)
                        .padding(.top, 10)
                    legend(report)
                        .padding(.top, 10)

                    sectionLabel("At a glance")
                        .padding(.top, 24)
                    facts(report)
                        .padding(.top, 8)

                    suggestion(results)

                    sectionLabel("Recent runs")
                        .padding(.top, 24)
                    recentRuns(report)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 36)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: - Header

    private func header(_ report: StepReport) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon = liveStep?.icon, !icon.isEmpty {
                Text(icon)
                    .font(.system(size: 30))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased())
                    .font(analogFont(22))
                    .tracking(1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(metaLine(report))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metaLine(_ report: StepReport) -> String {
        let kind: String
        if let liveStep {
            kind = liveStep.autoNext ? "AUTO" : "MANUAL"
        } else {
            kind = "NO LONGER IN ROUTINE"
        }
        let runs = report.runs.count == 1 ? "1 RUN" : "\(report.runs.count) RUNS"
        return "\(kind) · PLAN \(Self.clock(plannedSeconds)) · \(runs)"
    }

    // MARK: - Hero

    private func hero(_ report: StepReport) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                heroCell(label: "Typical", value: typicalText(report), color: .primary, detail: rangeText(report))
                hairline(vertical: true)
                heroCell(label: "Vs plan", value: deltaText(report), color: deltaColor(report), detail: overText(report))
            }
            .fixedSize(horizontal: false, vertical: true)
            hairline(vertical: false)
            Text(verdict(report))
                .font(analogFont(13))
                .tracking(0.4)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
        }
        .overlay(box)
    }

    private func heroCell(label: String, value: String, color: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            microLabel(label)
            Text(value)
                .font(analogFont(34))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func typicalText(_ report: StepReport) -> String {
        if let typical = report.typicalSeconds { return Self.clock(typical) }
        return report.isAutoOnly ? Self.clock(plannedSeconds) : "—"
    }

    private func rangeText(_ report: StepReport) -> String {
        if report.isAutoOnly { return "ENDS ON TIME" }
        if let range = report.usualRange {
            return "USUALLY \(Self.clock(range.lowerBound))–\(Self.clock(range.upperBound))"
        }
        if report.typicalSeconds == nil { return "AFTER 2 TIMED RUNS" }
        return "\(report.timed.count) TIMED RUNS"
    }

    private func deltaText(_ report: StepReport) -> String {
        if report.isAutoOnly { return "0:00" }
        guard let typical = report.typicalSeconds else { return "—" }
        return Self.signed(typical - plannedSeconds)
    }

    private func deltaColor(_ report: StepReport) -> Color {
        guard let typical = report.typicalSeconds else { return .primary }
        let delta = typical - plannedSeconds
        if delta > StepOutcome.onPlanToleranceSeconds { return Self.overColor }
        if delta < -StepOutcome.onPlanToleranceSeconds { return tint }
        return .primary
    }

    private func overText(_ report: StepReport) -> String {
        if report.isAutoOnly { return "AUTO STEP" }
        let timed = report.timed.count
        guard timed > 0 else { return "NO TIMED RUNS" }
        return "OVER IN \(report.count(.over)) OF \(timed)"
    }

    /// The page's answer in one sentence: where it usually lands against the
    /// plan, and which way it's heading.
    private func verdict(_ report: StepReport) -> String {
        if report.runs.isEmpty { return "No runs yet." }
        if report.isAutoOnly { return "An auto step — it always ends right on time." }
        guard let typical = report.typicalSeconds else {
            return "Not enough timed runs yet to say what's typical."
        }
        let delta = typical - plannedSeconds
        var sentence: String
        if abs(delta) <= StepOutcome.onPlanToleranceSeconds {
            sentence = "Usually right on plan"
        } else if delta > 0 {
            sentence = "Usually runs \(Self.clock(delta)) over"
        } else {
            sentence = "Usually done \(Self.clock(-delta)) early"
        }
        if let trend = report.trendSeconds {
            if trend <= -10 {
                sentence += ", and getting faster"
            } else if trend >= 10 {
                sentence += ", and getting slower"
            } else {
                sentence += ", and holding steady"
            }
        }
        return sentence + "."
    }

    // MARK: - Chart

    private func chart(_ report: StepReport) -> some View {
        let runs = report.runs
        let keys = runs.indices.map { "run-\($0)" }
        let edgeKeys = [keys.first, keys.last].compactMap { $0 }

        return Chart {
            if let range = report.usualRange {
                RectangleMark(
                    yStart: .value("Usual from", range.lowerBound),
                    yEnd: .value("Usual to", range.upperBound)
                )
                .foregroundStyle(Color.primary.opacity(0.07))
            }
            RuleMark(y: .value("Plan", plannedSeconds))
                .foregroundStyle(Color.primary.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                BarMark(
                    x: .value("Run", keys[index]),
                    y: .value("Took", run.result.actualSeconds),
                    width: .ratio(0.62)
                )
                .foregroundStyle(barColor(run.outcome))
            }
        }
        .chartXAxis {
            AxisMarks(values: edgeKeys) { value in
                AxisValueLabel {
                    if let key = value.as(String.self), let index = keys.firstIndex(of: key) {
                        Text(Self.shortDay.string(from: runs[index].sessionStart).uppercased())
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let seconds = value.as(Int.self) {
                        Text(Self.clock(seconds))
                            .font(.system(size: 8, weight: .medium))
                    }
                }
            }
        }
        .accessibilityLabel("Time taken on each run of \(title)")
    }

    private func barColor(_ outcome: StepOutcome) -> Color {
        switch outcome {
        case .over: return Self.overColor
        case .under: return tint
        case .onPlan: return Color.primary.opacity(0.55)
        case .auto: return Color.primary.opacity(0.25)
        case .cutShort, .skipped: return Color.secondary.opacity(0.35)
        }
    }

    private func legend(_ report: StepReport) -> some View {
        HStack(spacing: 12) {
            legendSwatch(Self.overColor, "Over")
            legendSwatch(tint, "Under")
            if report.count(.cutShort) + report.count(.skipped) > 0 {
                legendSwatch(Color.secondary.opacity(0.35), "Cut short")
            }
            HStack(spacing: 5) {
                Rectangle()
                    .stroke(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 12, height: 1)
                microLabel("Plan")
            }
            if report.usualRange != nil {
                legendSwatch(Color.primary.opacity(0.1), "Usual")
            }
        }
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 9, height: 9)
            microLabel(label)
        }
    }

    // MARK: - Facts

    private func facts(_ report: StepReport) -> some View {
        let cells: [(label: String, value: String, detail: String)] = [
            ("Best", report.best.map { Self.clock($0.result.actualSeconds) } ?? "—",
             report.best.map { Self.shortDay.string(from: $0.sessionStart).uppercased() } ?? "NO TIMED RUNS"),
            ("Slowest", report.slowest.map { Self.clock($0.result.actualSeconds) } ?? "—",
             report.slowest.map { Self.shortDay.string(from: $0.sessionStart).uppercased() } ?? "NO TIMED RUNS"),
            ("Starts", report.typicalStartOffsetSeconds.map { Self.clock($0) } ?? "—",
             "INTO THE ROUTINE"),
            ("Share", report.averageShareOfRoutine.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
             "OF THE ROUTINE"),
            ("Finished", "\(report.finishedCount)/\(report.runs.count)",
             "\(report.count(.cutShort)) CUT SHORT · \(report.count(.skipped)) SKIPPED"),
            ("On plan", report.isAutoOnly ? "AUTO" : "\(report.count(.onPlan))/\(report.timed.count)",
             "WITHIN 3 SECONDS"),
        ]

        return VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                if row > 0 { hairline(vertical: false) }
                HStack(spacing: 0) {
                    factCell(cells[row * 2])
                    hairline(vertical: true)
                    factCell(cells[row * 2 + 1])
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .overlay(box)
    }

    private func factCell(_ cell: (label: String, value: String, detail: String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            microLabel(cell.label)
            Text(cell.value)
                .font(analogFont(20))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(cell.detail)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Suggestion

    @ViewBuilder
    private func suggestion(_ results: [SessionResult]) -> some View {
        if let live = liveStep,
           let suggestion = RoutineStats(sessions: results).suggestions(for: [RunStep(live)]).first {
            VStack(alignment: .leading, spacing: 10) {
                microLabel("Suggestion")
                Text("Planned \(Self.clock(plannedSeconds)), but it usually takes about \(Self.clock(suggestion.averageActualSeconds)).")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ReceiptBarButton(title: "Set plan to \(Self.clock(suggestion.suggestedSeconds))") {
                    live.durationSeconds = suggestion.suggestedSeconds
                    try? modelContext.save()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .overlay(box)
            .padding(.top, 14)
        }
    }

    // MARK: - Recent runs

    private func recentRuns(_ report: StepReport) -> some View {
        let recent = Array(report.runs.reversed().prefix(10))

        return VStack(spacing: 0) {
            ForEach(Array(recent.enumerated()), id: \.offset) { index, run in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Self.longDay.string(from: run.sessionStart).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.clock(run.result.actualSeconds))
                        .font(analogFont(15))
                        .monospacedDigit()
                    Text(runDetail(run))
                        .font(analogFont(11))
                        .monospacedDigit()
                        .foregroundStyle(runDetailColor(run.outcome))
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func runDetail(_ run: StepReport.Run) -> String {
        switch run.outcome {
        case .cutShort: return "CUT"
        case .skipped: return "SKIP"
        case .auto: return "AUTO"
        case .over, .under, .onPlan: return Self.signed(run.result.deltaSeconds)
        }
    }

    private func runDetailColor(_ outcome: StepOutcome) -> Color {
        switch outcome {
        case .over: return Self.overColor
        case .under: return tint
        case .onPlan, .auto, .cutShort, .skipped: return .secondary
        }
    }

    // MARK: - Pieces

    private var box: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
    }

    private func hairline(vertical: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }

    private func sectionLabel(_ text: String) -> some View {
        microLabel(text)
    }

    private func microLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(.secondary)
    }

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

    private static func clock(_ seconds: Int) -> String {
        TimeFormatting.clockTime(from: seconds)
    }

    private static func signed(_ seconds: Int) -> String {
        guard abs(seconds) > StepOutcome.onPlanToleranceSeconds else { return "0:00" }
        return (seconds < 0 ? "−" : "+") + TimeFormatting.clockTime(from: seconds)
    }
}
