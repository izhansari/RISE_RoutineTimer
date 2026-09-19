//
//  RunRingView.swift
//  RISE_RoutineTimer
//
//  Where the time went: the run as a ring, one slice per step, sized by how
//  long the step took. Slices run clockwise from twelve in the order they
//  happened, so the ring is also a clock face of the morning — coffee is a
//  third of the dial, the four shower steps are a cluster of slivers.
//
//  The rows beneath it in the summary measure each step against *its own
//  plan*, which deliberately puts a one-minute step and a twelve-minute step
//  on the same footing. This is the other question: which steps the routine
//  is actually made of.
//
//  Every slice is a pale tint of how its step went — the amber a step running
//  over turns the timer, the theme colour for under, grey for on plan — so the
//  slow steps show before anything is touched. The selected slice goes solid
//  and grows past the others. Tap a slice, or press and drag round the ring;
//  it opens on the biggest one, which is the answer most people came for.
//
//  The maths is `RunComposition`.
//

import Charts
import SwiftUI
import UIKit

struct RunRingView: View {
    let composition: RunComposition
    /// Step results carry no icon; these are looked up from the routine.
    let icons: [UUID: String]
    let tint: Color
    let over: Color

    /// Nil until a slice has been touched, and the ring shows the biggest.
    /// Kept as a choice rather than resolved on appear so a run corrected
    /// from EDIT re-opens on whatever is biggest *now*.
    @State private var chosen: Int?
    /// Where on the ring the finger is, in seconds into the run. Swift Charts
    /// clears it the moment the touch ends, so it is only ever an input.
    @State private var touch: Double?

    private let diameter: CGFloat = 214
    private let innerRatio = 0.6

    private var selected: RunComposition.Slice? {
        let index = chosen ?? composition.largestIndex
        return composition.slices.first { $0.index == index }
    }

    var body: some View {
        let selected = selected

        VStack(spacing: 14) {
            ZStack {
                Chart(composition.slices) { slice in
                    let isSelected = slice.index == selected?.index
                    SectorMark(
                        angle: .value("Took", Double(max(0, slice.result.actualSeconds))),
                        innerRadius: .ratio(innerRatio),
                        outerRadius: .ratio(isSelected ? 1 : 0.89),
                        angularInset: 1
                    )
                    .foregroundStyle(color(slice.outcome, selected: isSelected))
                    .accessibilityLabel(slice.result.title)
                    .accessibilityValue(
                        "took \(TimeFormatting.spokenDuration(from: slice.result.actualSeconds)), \(Self.percent(slice.share)) of the run"
                    )
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $touch)
                .animation(.snappy(duration: 0.28), value: selected?.index)

                if let selected {
                    centre(selected)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: diameter, height: diameter)
            // A tap is hit-tested by hand; the chart's own selection, above,
            // only wakes after a short press inside a scroll view, and is
            // kept for pressing and dragging round the ring.
            .simultaneousGesture(
                SpatialTapGesture().onEnded { tap in
                    let size = CGSize(width: diameter, height: diameter)
                    guard let index = composition.index(at: tap.location, inRingOf: size, innerRatio: innerRatio) else { return }
                    choose(index)
                }
            )
            .frame(maxWidth: .infinity)

            if let selected {
                caption(selected)
            }
        }
        .onChange(of: touch) { _, seconds in
            guard let seconds, let index = composition.index(atSeconds: seconds) else { return }
            choose(index)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Where the time went")
    }

    private func choose(_ index: Int) {
        guard index != selected?.index else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        chosen = index
    }

    // MARK: - Readout

    /// How long, and how much of the run. Values cut rather than roll, the
    /// same rule as every other number in the app.
    private func centre(_ slice: RunComposition.Slice) -> some View {
        VStack(spacing: 3) {
            Text(TimeFormatting.clockTime(from: slice.result.actualSeconds))
                .font(analogFont(32))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(Self.percent(slice.share)) OF THE RUN")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
        }
        .frame(width: diameter * 0.52)
        .contentTransition(.identity)
        .transaction { $0.animation = nil }
    }

    /// The step's name, and how it went against its plan. Two fixed-height
    /// lines, so a long name never moves the rows below.
    private func caption(_ slice: RunComposition.Slice) -> some View {
        let icon = icons[slice.result.stepID] ?? ""

        return VStack(spacing: 5) {
            HStack(spacing: 7) {
                if !icon.isEmpty {
                    Text(icon).font(.system(size: 15))
                }
                Text(slice.result.title.uppercased())
                    .font(analogFont(15))
                    .tracking(1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(height: 20)

            Text(verdict(slice))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(verdictColor(slice.outcome))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 13)
        }
        .frame(maxWidth: .infinity)
        .contentTransition(.identity)
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .combine)
    }

    private func verdict(_ slice: RunComposition.Slice) -> String {
        let step = slice.result
        let plan = "PLAN \(TimeFormatting.clockTime(from: step.plannedSeconds))"
        let share = Int((abs(step.shareOfPlan) * 100).rounded())
        let time = TimeFormatting.clockTime(from: step.deltaSeconds)

        switch slice.outcome {
        case .over:     return "\(share)% OVER · +\(time) · \(plan)"
        case .under:    return "\(share)% UNDER · −\(time) · \(plan)"
        case .onPlan:   return "ON PLAN · \(plan)"
        case .auto:     return "AUTO · ON PLAN · \(plan)"
        case .cutShort: return "CUT SHORT · \(plan)"
        case .skipped:  return "SKIPPED · \(plan)"
        }
    }

    // MARK: - Colour

    private func color(_ outcome: StepOutcome, selected: Bool) -> Color {
        switch outcome {
        case .over:
            return over.opacity(selected ? 1 : 0.32)
        case .under:
            return tint.opacity(selected ? 1 : 0.3)
        case .onPlan, .auto:
            return Color.primary.opacity(selected ? 0.85 : 0.13)
        case .cutShort, .skipped:
            return Color.primary.opacity(selected ? 0.4 : 0.06)
        }
    }

    private func verdictColor(_ outcome: StepOutcome) -> Color {
        switch outcome {
        case .over: return over
        case .under: return tint
        case .onPlan, .auto, .cutShort, .skipped: return .secondary
        }
    }

    private static func percent(_ share: Double) -> String {
        let value = share * 100
        // Below one percent a rounded "0%" would say the step took nothing.
        if value > 0, value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }
}
