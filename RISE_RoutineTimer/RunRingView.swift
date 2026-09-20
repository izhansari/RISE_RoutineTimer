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
//  and grows past the others. Tap a slice, or step round the ring with the
//  arrows beside the step's name; it opens on the biggest one, which is the
//  answer most people came for.
//
//  Drawn with SwiftUI shapes, not Swift Charts. The first version was a
//  `Chart` of `SectorMark`s, and selecting a slice played two transitions:
//  Charts does not interpolate a mark's radius and colour, it takes the
//  changed mark out and puts it back — so the new slice vanished, faded in
//  grown but still pale, the old one sat there solid for the whole half
//  second, and the colours swapped in one frame at the end. A `Shape` with an
//  animatable radius and an animated fill does the one movement that was
//  meant. Charts was already not doing the hit-testing (it ignores a plain
//  tap inside a scroll view), so nothing was lost by dropping it.
//
//  The maths is `RunComposition`.
//

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

    private let diameter: CGFloat = 214
    private let innerRatio = 0.6
    private let restingRatio = 0.89

    private var selected: RunComposition.Slice? {
        let index = chosen ?? composition.largestIndex
        return composition.slices.first { $0.index == index }
    }

    private var ringSize: CGSize { CGSize(width: diameter, height: diameter) }

    var body: some View {
        let selected = selected
        let total = Double(max(1, composition.totalSeconds))

        VStack(spacing: 14) {
            ZStack {
                ForEach(composition.slices) { slice in
                    let isSelected = slice.index == selected?.index
                    RingSlice(
                        start: Double(slice.startSeconds) / total,
                        end: Double(slice.endSeconds) / total,
                        innerRatio: innerRatio,
                        outerRatio: isSelected ? 1 : restingRatio
                    )
                    .fill(color(slice.outcome, selected: isSelected))
                    .accessibilityElement()
                    .accessibilityLabel(slice.result.title)
                    .accessibilityValue(
                        "took \(TimeFormatting.spokenDuration(from: slice.result.actualSeconds)), \(Self.percent(slice.share)) of the run"
                    )
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { choose(slice.index) }
                }
                // One movement: the old slice settles back as the new one
                // comes forward, colour and radius together. No bounce — a
                // spring's overshoot on a radius reads as a second, smaller
                // transition, which is the thing this replaced.
                .animation(.easeOut(duration: 0.22), value: selected?.index)

                if let selected {
                    centre(selected)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            // A tap picks the slice under it, and a tap is the *only* gesture
            // here. Pressing and dragging round the ring was built and taken
            // out again: any drag gesture on a view inside a scroll view —
            // even one gated behind a long press — swallowed swipes that
            // began on the ring, and the ring sits exactly where a thumb
            // goes to scroll the summary. The steppers beside the name do
            // the fine work instead.
            .simultaneousGesture(
                SpatialTapGesture().onEnded { tap in
                    guard let index = composition.index(at: tap.location, inRingOf: ringSize, innerRatio: innerRatio) else { return }
                    choose(index)
                }
            )
            .frame(maxWidth: .infinity)

            if let selected {
                caption(selected)
            }
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

        return HStack(spacing: 4) {
            stepper("chevron.left", label: "Previous step", to: composition.neighbour(of: slice.index, by: -1))
            captionText(slice, icon: icon)
            stepper("chevron.right", label: "Next step", to: composition.neighbour(of: slice.index, by: 1))
        }
        .accessibilityElement(children: .contain)
    }

    /// Walks the selection one slice round the ring.
    private func stepper(_ systemName: String, label: String, to index: Int?) -> some View {
        Button {
            if let index { choose(index) }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func captionText(_ slice: RunComposition.Slice, icon: String) -> some View {
        VStack(spacing: 5) {
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

// MARK: - One slice

/// A sector of the ring, in turns clockwise from twelve. Only the outer
/// radius animates; the angles belong to the run and never move.
///
/// The gap between slices is a constant width rather than a constant angle,
/// so it stays a hairline at the rim instead of fanning out — which means the
/// inset is a different angle at the inner edge than at the outer one.
nonisolated private struct RingSlice: Shape {
    var start: Double
    var end: Double
    var innerRatio: Double
    var outerRatio: Double
    var gap: Double = 2

    var animatableData: Double {
        get { outerRatio }
        set { outerRatio = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = Double(min(rect.width, rect.height)) / 2
        let outer = radius * outerRatio
        let inner = radius * innerRatio
        let sweep = (end - start) * 2 * Double.pi
        guard sweep > 0, outer > inner, inner > 0 else { return Path() }

        // A sliver keeps a fifth of itself rather than being eaten by its
        // own gaps.
        let outerInset = min(asin(min(1, gap / 2 / outer)), sweep * 0.4)
        let innerInset = min(asin(min(1, gap / 2 / inner)), sweep * 0.4)

        let from = start * 2 * Double.pi - Double.pi / 2
        let to = from + sweep
        let centre = CGPoint(x: rect.midX, y: rect.midY)

        var path = Path()
        // `clockwise: false` is clockwise on screen: SwiftUI's y axis points down.
        path.addArc(center: centre, radius: outer,
                    startAngle: .radians(from + outerInset), endAngle: .radians(to - outerInset), clockwise: false)
        path.addArc(center: centre, radius: inner,
                    startAngle: .radians(to - innerInset), endAngle: .radians(from + innerInset), clockwise: true)
        path.closeSubpath()
        return path
    }
}
