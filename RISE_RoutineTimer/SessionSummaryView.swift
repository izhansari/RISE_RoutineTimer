//
//  SessionSummaryView.swift
//  RISE_RoutineTimer
//
//  How a run went, step by step. Shown the moment a routine finishes, and
//  again from any session in History.
//
//  Each step is measured against its own plan: the bar is the share of plan
//  it ran over or under, on a ±100% scale, so a five-minute step and a
//  one-minute step sit on the same footing and nothing needs clipping. The
//  time it took is the number on the right; tapping a row swaps the
//  percentage beneath it for the time over or under.
//
//  Steps that barely happened (see `SessionBreakdown`) are drawn as a grey
//  hatch and left out of the pace number in the header.
//

import SwiftData
import SwiftUI
import UIKit

struct SessionSummaryView: View {
    enum Context { case justFinished, history }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]
    @Query private var routineSteps: [RoutineStep]
    @AppStorage(FillTheme.storageKey) private var fillThemeRaw = FillTheme.default.rawValue

    let result: SessionResult
    var context: Context = .justFinished

    /// Rows showing time over / under instead of share of plan.
    @State private var flipped: Set<Int> = []

    /// Wide enough for "TOWEL / MOUTHWASH" in the receipt face; the bar
    /// gets what is left, which is still plenty for a ±100% scale.
    private let nameWidth: CGFloat = 128
    private let valueWidth: CGFloat = 52

    private var breakdown: SessionBreakdown { SessionBreakdown(steps: result.steps) }
    private var tint: Color { (FillTheme(rawValue: fillThemeRaw) ?? .default).color }
    private static let overColor = Color(hex: 0xE8890A)

    /// Step results carry no icon, so glyphs come from the routine by id. A
    /// step deleted since the run simply goes without.
    private var icons: [UUID: String] {
        Dictionary(routineSteps.map { ($0.stepID, $0.icon) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let breakdown = breakdown

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, 20)
                timeRange
                    .padding(.top, 12)
                hero(breakdown)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                ReceiptRule()

                axisHeader
                    .padding(.top, 12)
                    .padding(.bottom, 2)

                ForEach(breakdown.rows) { row in
                    rowView(row)
                    if row.id != breakdown.rows.last?.id {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                    }
                }

                Text("TAP A STEP FOR TIME OVER OR UNDER")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)

                if context == .justFinished, let comparison {
                    ReceiptRule()
                        .padding(.top, 18)
                    Text(comparison)
                        .font(analogFont(14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    // MARK: - Header

    private var topBar: some View {
        HStack(alignment: .center) {
            Text(statusLine)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            Spacer()
            Button { dismiss() } label: {
                Text("DONE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary, lineWidth: 1.2))
            }
            .buttonStyle(.plain)
        }
    }

    private var statusLine: String {
        let day = Self.dayFormatter.string(from: result.startedAt).uppercased()
        return "\(day) · \(result.completed ? "COMPLETE" : "ENDED EARLY")"
    }

    /// When it happened, not only how long it took — the clock times are what
    /// you line up against the rest of the morning.
    private var timeRange: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TimeFormatting.clockRange(from: result.startedAt, to: result.endedAt))
                .font(analogFont(28))
                .tracking(1)
                .monospacedDigit()
            if result.pausedSeconds >= 60 {
                Text("PAUSED \(TimeFormatting.durationText(from: result.pausedSeconds).uppercased())")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func hero(_ breakdown: SessionBreakdown) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                microLabel("Took")
                Text(TimeFormatting.clockTime(from: result.activeSeconds))
                    .font(analogFont(46))
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                microLabel(breakdown.barelyHappenedCount > 0
                           ? "\(breakdown.pacedStepCount) steps vs plan"
                           : "Vs plan")
                Text(Self.signed(breakdown.pacedDeltaSeconds))
                    .font(analogFont(22))
                    .monospacedDigit()
                    .foregroundStyle(deltaColor(breakdown.pacedDeltaSeconds))
                if breakdown.barelyHappenedCount > 0 {
                    HStack(spacing: 5) {
                        HatchSwatch()
                            .frame(width: 9, height: 9)
                        Text("\(breakdown.barelyHappenedCount) CUT SHORT")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
                    .padding(.top, 2)
                }
            }
        }
    }

    private var axisHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 20, height: 1)
            microLabel("Step")
                .frame(width: nameWidth, alignment: .leading)
            HStack(spacing: 0) {
                microLabel("−100%")
                Spacer(minLength: 0)
                microLabel("Plan")
                Spacer(minLength: 0)
                microLabel("+100%")
            }
            microLabel("Took")
                .frame(width: valueWidth, alignment: .trailing)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(_ row: SessionBreakdown.Row) -> some View {
        let isFlipped = flipped.contains(row.id)

        switch row {
        case .step(_, let step, let outcome):
            HStack(spacing: 8) {
                glyph(for: step, dimmed: outcome.barelyHappened)
                Text(step.title.uppercased())
                    .font(analogFont(11))
                    .tracking(0.3)
                    .lineLimit(1)
                    .foregroundStyle(outcome.barelyHappened ? .secondary : .primary)
                    .frame(width: nameWidth, alignment: .leading)
                ShareBar(share: step.shareOfPlan, outcome: outcome, tint: tint, over: Self.overColor)
                valueColumn(
                    took: step.actualSeconds,
                    detail: detailText(step, outcome: outcome, flipped: isFlipped),
                    color: detailColor(outcome)
                )
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { flip(row.id) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(step, outcome: outcome))
            .accessibilityHint("Switches between percent of plan and time over or under")

        case .autoRun(_, let steps):
            let took = steps.reduce(0) { $0 + $1.actualSeconds }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    HStack(spacing: -6) {
                        ForEach(Array(steps.prefix(5).enumerated()), id: \.offset) { _, step in
                            Text(icons[step.stepID] ?? "")
                                .font(.system(size: 10))
                                .frame(width: 15, height: 15)
                                .background(Circle().fill(Color(.systemBackground)))
                        }
                    }
                    Text("\(steps.count) AUTO")
                        .font(analogFont(11))
                        .tracking(0.3)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 20 + 8 + nameWidth, alignment: .leading)
                ShareBar(share: 0, outcome: .auto, tint: tint, over: Self.overColor)
                valueColumn(took: took, detail: isFlipped ? "0:00" : "0%", color: .secondary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { flip(row.id) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(steps.count) auto steps, took \(TimeFormatting.spokenDuration(from: took)), on plan")
        }
    }

    private func glyph(for step: StepResult, dimmed: Bool) -> some View {
        let icon = icons[step.stepID] ?? ""
        return Group {
            if icon.isEmpty {
                Circle().fill(Color.primary.opacity(0.15)).frame(width: 5, height: 5)
            } else {
                Text(icon).font(.system(size: 14))
            }
        }
        .frame(width: 20, height: 20)
        .grayscale(dimmed ? 1 : 0)
        .opacity(dimmed ? 0.5 : 1)
    }

    private func valueColumn(took: Int, detail: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(TimeFormatting.clockTime(from: took))
                .font(analogFont(15))
                .monospacedDigit()
            Text(detail)
                .font(analogFont(11))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(width: valueWidth, alignment: .trailing)
    }

    private func flip(_ id: Int) {
        if flipped.contains(id) { flipped.remove(id) } else { flipped.insert(id) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func detailText(_ step: StepResult, outcome: StepOutcome, flipped: Bool) -> String {
        if flipped { return Self.signed(step.deltaSeconds) }
        if outcome == .skipped { return "SKIP" }
        return Self.percent(step.shareOfPlan)
    }

    private func detailColor(_ outcome: StepOutcome) -> Color {
        switch outcome {
        case .over: return Self.overColor
        case .under: return tint
        case .cutShort, .skipped, .onPlan, .auto: return .secondary
        }
    }

    private func deltaColor(_ seconds: Int) -> Color {
        if seconds > StepOutcome.onPlanToleranceSeconds { return Self.overColor }
        if seconds < -StepOutcome.onPlanToleranceSeconds { return tint }
        return .primary
    }

    private func accessibilityText(_ step: StepResult, outcome: StepOutcome) -> String {
        let took = TimeFormatting.spokenDuration(from: step.actualSeconds)
        let planned = TimeFormatting.spokenDuration(from: step.plannedSeconds)
        let verdict: String
        switch outcome {
        case .over: verdict = "\(TimeFormatting.spokenDuration(from: step.deltaSeconds)) over"
        case .under: verdict = "\(TimeFormatting.spokenDuration(from: -step.deltaSeconds)) under"
        case .onPlan: verdict = "on plan"
        case .cutShort: verdict = "cut short"
        case .skipped: verdict = "skipped"
        case .auto: verdict = "auto, on plan"
        }
        return "\(step.title), took \(took) of \(planned), \(verdict)"
    }

    private func microLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(.secondary)
    }

    // MARK: - Comparison

    private var comparison: String? {
        let stats = RoutineStats(sessions: sessions.map(\.result))
        guard stats.count >= 2, let average = stats.averageActiveSeconds, let best = stats.bestActiveSeconds else {
            return "First one in the books. Averages start next time."
        }
        var parts = ["Average \(TimeFormatting.clockTime(from: average))"]
        if result.activeSeconds <= best {
            parts.append("new best")
        } else {
            parts.append("best \(TimeFormatting.clockTime(from: best))")
        }
        let streak = stats.currentStreak()
        if streak >= 2 {
            parts.append("\(streak) day streak")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Formatting

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static func signed(_ seconds: Int) -> String {
        guard abs(seconds) > StepOutcome.onPlanToleranceSeconds else { return "0:00" }
        return (seconds < 0 ? "−" : "+") + TimeFormatting.clockTime(from: seconds)
    }

    private static func percent(_ share: Double) -> String {
        let value = Int((share * 100).rounded())
        guard value != 0 else { return "0%" }
        return (value < 0 ? "−" : "+") + "\(abs(value))%"
    }
}

// MARK: - Share bar

/// One step against its own plan: a centre axis, a bar left for under and
/// right for over, clamped at ±100%. Barely-happened steps are a grey hatch
/// rather than the theme colour — rushing is not the same as being quick.
private struct ShareBar: View {
    let share: Double
    let outcome: StepOutcome
    let tint: Color
    let over: Color

    private let barHeight: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let mid = width / 2
            let length = max(1.5, CGFloat(min(1, abs(share))) * mid)

            ZStack(alignment: .topLeading) {
                ForEach([0.25, 0.75], id: \.self) { f in
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 1, height: height - 6)
                        .offset(x: width * f, y: 3)
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.22))
                    .frame(width: 1, height: height)
                    .offset(x: mid)

                switch outcome {
                case .onPlan, .auto:
                    Circle()
                        .fill(Color(.systemBackground))
                        .overlay(Circle().strokeBorder(Color.secondary, lineWidth: 1.4))
                        .frame(width: 6, height: 6)
                        .offset(x: mid - 2.5, y: height / 2 - 3)
                case .over:
                    Rectangle()
                        .fill(over)
                        .frame(width: length, height: barHeight)
                        .offset(x: mid + 0.5, y: (height - barHeight) / 2)
                case .under:
                    Rectangle()
                        .fill(tint)
                        .frame(width: length, height: barHeight)
                        .offset(x: mid - length, y: (height - barHeight) / 2)
                case .cutShort, .skipped:
                    HatchSwatch()
                        .frame(width: length, height: barHeight)
                        .offset(x: mid - length, y: (height - barHeight) / 2)
                }
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// Diagonal grey hatching inside a hairline box — the mark for a step that
/// barely happened.
private struct HatchSwatch: View {
    var body: some View {
        Hatch()
            .stroke(Color.secondary.opacity(0.75), lineWidth: 1)
            .clipped()
            .overlay(Rectangle().strokeBorder(Color.secondary.opacity(0.75), lineWidth: 1))
    }
}

private struct Hatch: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 3.5
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
