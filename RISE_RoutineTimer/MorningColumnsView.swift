//
//  MorningColumnsView.swift
//  RISE_RoutineTimer
//
//  Draws `MorningColumn`s against a `ClockScale`: the chart History and Today
//  share. See `MorningColumns.swift` for what the mark means.
//
//  Plain SwiftUI shapes, not Swift Charts — the ring in the session summary
//  is the record of why (Charts animates a changed mark as two transitions,
//  and ignores a plain tap inside a scroll view).
//

import SwiftUI
import UIKit

enum MorningColumnInk {
    static let goal = Color(hex: 0xE8890A)
    static let lag = Color(hex: 0x9B9B9B)
}

// MARK: - One mark

/// Every part is always in the tree, at zero height until it exists, and
/// whichever part has no end yet runs to `now` — so the morning that is still
/// happening grows rather than popping in.
struct MorningColumnMark: View {
    let column: MorningColumn
    /// The live edge, for a column whose morning is not over.
    var now: Int? = nil
    let scale: ClockScale
    let height: CGFloat
    let tint: Color
    var faded = false

    private func y(_ minutes: Int) -> CGFloat { CGFloat(scale.fraction(minutes)) * height }

    var body: some View {
        // The dotted stretch is measured from *this morning's* goal.
        let goal = column.goal
        let snoozeTo = column.wake ?? now ?? goal
        let lagTo = column.start ?? now ?? column.wake ?? goal
        let boxTo = column.end ?? now ?? column.start ?? goal
        let showsSnooze = column.wake != nil || now != nil

        ZStack(alignment: .top) {
            VerticalLine()
                .stroke(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                .frame(width: 2, height: showsSnooze ? abs(y(snoozeTo) - y(goal)) : 0)
                .offset(y: min(y(goal), y(snoozeTo)))
            Rectangle().fill(MorningColumnInk.lag)
                .frame(width: 2, height: column.wake == nil ? 0 : max(0, y(lagTo) - y(column.wake ?? goal)))
                .offset(y: y(column.wake ?? snoozeTo))
            Rectangle().fill(Color.primary)
                .frame(width: 14, height: 2)
                .offset(y: y(column.wake ?? snoozeTo) - 1)
                .opacity(column.wake == nil ? 0 : 1)
            Rectangle().fill(tint)
                .frame(width: 12, height: column.start == nil ? 0 : max(0, y(boxTo) - y(column.start ?? goal)))
                .offset(y: y(column.start ?? lagTo))
            // A pause: the clock ran on, the routine did not.
            if let end = column.end, let pausedUntil = column.pausedUntil {
                Rectangle()
                    .strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 12, height: max(0, y(pausedUntil) - y(end)))
                    .offset(y: y(end))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .opacity(faded ? 0.32 : 1)
    }
}

private struct VerticalLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct HorizontalLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - The chart

/// A row of columns on one clock, with hour rules, the dashed goal line and
/// day labels. With a `selection` binding it answers a tap or a sideways
/// slide; without one it is a picture.
struct MorningColumnsChart: View {
    let columns: [MorningColumn]
    let scale: ClockScale
    let tint: Color
    var height: CGFloat = 250
    /// The index of the selected column. Nil binding: not interactive.
    var selection: Binding<Int?>? = nil
    /// The column still being lived, and the moment it has reached.
    var liveIndex: Int? = nil
    var now: Int? = nil
    /// Everything but the live column drawn back, as context.
    var fadesHistory = false
    /// Label the selected column's marks in place, rather than reporting it
    /// somewhere else. Today uses this so selecting a day cannot move
    /// anything on a screen that has to fit exactly once.
    var annotatesSelection = false
    /// Night columns have their cap at the start, so the gap label between
    /// cap and box (always "0m") is left off and the spoken form says
    /// "started" rather than "woke".
    var kind: RoutineKind = .morning
    let label: (MorningColumn) -> String

    private let gutter: CGFloat = 36
    /// The day-number strip under the plot, plus the gap above it.
    static let labelStripHeight: CGFloat = 18

    private func y(_ minutes: Int) -> CGFloat { CGFloat(scale.fraction(minutes)) * height }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                hourLabels
                GeometryReader { geo in
                    let step = geo.size.width / CGFloat(max(1, columns.count))
                    plot(step: step)
                        .contentShape(Rectangle())
                        .modifier(ColumnSelection(selection: selection, step: step, count: columns.count))
                }
                .frame(height: height)
            }
            HStack(spacing: 6) {
                Color.clear.frame(width: gutter, height: 12)
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        let strong = index == selection?.wrappedValue || index == liveIndex
                        Text(label(column))
                            .font(.system(size: 9, weight: strong ? .bold : .semibold))
                            .foregroundStyle(strong ? .primary : .tertiary)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        // The readout around this cuts to its values; so does the chart.
        .transaction { $0.animation = nil }
    }

    private func plot(step: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(scale.hours, id: \.self) { hour in
                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).offset(y: y(hour))
            }
            if let band = selection?.wrappedValue ?? liveIndex {
                Rectangle().fill(Color.primary.opacity(0.055))
                    .frame(width: step, height: height)
                    .offset(x: CGFloat(band) * step)
            }
            goalPath(step: step)
                .stroke(MorningColumnInk.goal, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    MorningColumnMark(
                        column: column,
                        now: index == liveIndex ? now : nil,
                        scale: scale, height: height, tint: tint,
                        faded: fadesHistory && index != liveIndex
                    )
                    .frame(width: step)
                    .accessibilityElement()
                    .accessibilityLabel(Self.spoken(column, label: label(column), kind: kind))
                    .accessibilityAddTraits(selection == nil ? [] : .isButton)
                    .accessibilityAction { selection?.wrappedValue = index }
                }
            }

            if annotatesSelection, let index = selection?.wrappedValue,
               columns.indices.contains(index), columns[index].hasAnything {
                annotations(columns[index], at: index, step: step)
            }
        }
        .frame(height: height, alignment: .top)
    }

    /// The selected day's numbers, floated beside its own marks: the clock
    /// time at the cap, how long until the routine started against the
    /// whisker, and the routine's length against the box.
    ///
    /// Drawn as an overlay inside the plot, so selecting a day changes
    /// nothing about the layout — on a screen built to fit exactly once, a
    /// readout that appeared underneath would shove everything else.
    ///
    /// All three always show. They used to be dropped whenever their mark
    /// was too short to hang a label on, which on a compressed chart meant
    /// most days showed one label, some showed two and a rare long morning
    /// showed three — the reading changed as you dragged, which is worse
    /// than a tight fit. Now they are laid out and nudged apart instead.
    @ViewBuilder
    private func annotations(_ column: MorningColumn, at index: Int, step: CGFloat) -> some View {
        let centre = (CGFloat(index) + 0.5) * step
        // Labels sit on whichever side of the column has room.
        let onLeft = index > columns.count / 2

        ForEach(placedLabels(column), id: \.text) { label in
            chip(label.text, color: label.color, x: centre, y: label.y, onLeft: onLeft)
        }
    }

    private struct PlacedLabel {
        var y: CGFloat
        let text: String
        let color: Color
    }

    /// The labels this column has, at their marks, then spread apart so none
    /// sits on top of another and none escapes the plot.
    private func placedLabels(_ column: MorningColumn) -> [PlacedLabel] {
        var labels: [PlacedLabel] = []
        if let wake = column.wake {
            labels.append(PlacedLabel(y: y(wake), text: MorningColumnsChart.clockText(wake), color: .primary))
        }
        if kind == .morning, let wake = column.wake, let start = column.start, let lag = column.lag {
            labels.append(PlacedLabel(y: (y(wake) + y(start)) / 2, text: "\(lag)m", color: MorningColumnInk.lag))
        }
        if let start = column.start, let end = column.end, let minutes = column.routineMinutes {
            labels.append(PlacedLabel(y: (y(start) + y(end)) / 2, text: "\(minutes)m", color: tint))
        }
        guard labels.count > 1 else { return labels }

        // Push down through the stack, then back up if that ran off the
        // bottom — the same two passes the Today timeline's captions used.
        let gap = Self.chipHeight
        for index in 1..<labels.count {
            labels[index].y = max(labels[index].y, labels[index - 1].y + gap)
        }
        let bottom = height - gap / 2
        if let last = labels.last, last.y > bottom {
            labels[labels.count - 1].y = bottom
            for index in stride(from: labels.count - 2, through: 0, by: -1) {
                labels[index].y = min(labels[index].y, labels[index + 1].y - gap)
            }
        }
        let top = gap / 2
        if let first = labels.first, first.y < top {
            labels[0].y = top
            for index in 1..<labels.count {
                labels[index].y = max(labels[index].y, labels[index - 1].y + gap)
            }
        }
        return labels
    }

    /// A fixed width, so a label lands the same distance from its column
    /// whatever it says.
    private static let chipWidth: CGFloat = 42
    private static let chipHeight: CGFloat = 15

    private func chip(_ text: String, color: Color, x: CGFloat, y: CGFloat, onLeft: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.vertical, 1.5)
            .frame(width: Self.chipWidth, alignment: onLeft ? .trailing : .leading)
            .background(Color(.systemBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
            .position(x: x + (onLeft ? -(Self.chipWidth / 2 + 9) : Self.chipWidth / 2 + 9), y: y)
            .allowsHitTesting(false)
    }

    /// The goal line, stepping wherever the goal changed. A straight line
    /// would say the standard had always been today's — which for an app
    /// whose whole purpose is moving the wake time earlier is precisely the
    /// wrong story. A step says "I raised the bar on the 17th".
    private func goalPath(step: CGFloat) -> Path {
        var path = Path()
        for (index, column) in columns.enumerated() {
            let left = CGFloat(index) * step
            let line = y(column.goal)
            if index == 0 {
                path.move(to: CGPoint(x: left, y: line))
            } else if columns[index - 1].goal != column.goal {
                // Vertical riser at the boundary, then on across this day.
                path.addLine(to: CGPoint(x: left, y: line))
            }
            path.addLine(to: CGPoint(x: left + step, y: line))
        }
        return path
    }

    private var hourLabels: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(scale.hours, id: \.self) { hour in
                Text(Self.hourText(hour))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(y: y(hour) - 6)
            }
        }
        .frame(width: gutter, height: height, alignment: .topTrailing)
        .accessibilityHidden(true)
    }

    nonisolated static func hourText(_ minutes: Int) -> String {
        let hour = ((minutes / 60) % 24 + 24) % 24
        return "\((hour + 11) % 12 + 1)\(hour < 12 ? "AM" : "PM")"
    }

    /// "11:52", for a moment `minutes` into a day.
    nonisolated static func clockText(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return "\((m / 60 + 11) % 12 + 1):" + String(format: "%02d", m % 60)
    }

    private static func spoken(_ column: MorningColumn, label: String, kind: RoutineKind) -> String {
        guard column.hasAnything else { return "\(label), nothing logged" }
        var parts = [label]
        if let wake = column.wake { parts.append("\(kind == .night ? "started" : "woke") \(clockText(wake))") }
        if kind == .morning, let lag = column.lag { parts.append("\(lag) minutes to start") }
        if let routine = column.routineMinutes { parts.append("routine \(routine) minutes") }
        return parts.joined(separator: ", ")
    }
}

/// Tap a column, or slide sideways across them.
///
/// The slide is a UIKit pan that only *begins* when the movement is mostly
/// horizontal. Two SwiftUI versions came first and both broke the page: a
/// `DragGesture` — attached with `.gesture`, or with `.simultaneousGesture`
/// and a twelve-point threshold and a horizontal test of its own — swallowed
/// every vertical swipe that started on the chart, and this chart sits at
/// the top of a page that has to scroll. A recognizer that declines to begin
/// never enters the contest, so the list's own pan gets the vertical ones.
/// `UIGestureRecognizerRepresentable` is iOS 18; on 17 a tap still selects.
private struct ColumnSelection: ViewModifier {
    let selection: Binding<Int?>?
    let step: CGFloat
    let count: Int

    func body(content: Content) -> some View {
        if let selection, count > 0, step > 0 {
            let tappable = content.simultaneousGesture(
                SpatialTapGesture().onEnded { tap in
                    let index = self.index(at: tap.location.x)
                    UISelectionFeedbackGenerator().selectionChanged()
                    selection.wrappedValue = selection.wrappedValue == index ? nil : index
                }
            )
            if #available(iOS 18.0, *) {
                tappable.gesture(HorizontalPan { x in
                    let index = self.index(at: x)
                    guard index != selection.wrappedValue else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    selection.wrappedValue = index
                })
            } else {
                tappable
            }
        } else {
            content
        }
    }

    private func index(at x: CGFloat) -> Int {
        min(max(Int(x / step), 0), count - 1)
    }
}

@available(iOS 18.0, *)
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    /// The finger's x, in the chart's own coordinates.
    let onChanged: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        onChanged(context.converter.localLocation.x)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }
    }
}

// MARK: - Legend

struct MorningColumnsLegend: View {
    let tint: Color
    var kind: RoutineKind = .morning

    var body: some View {
        HStack(spacing: 12) {
            item("Goal") { HorizontalLine().stroke(MorningColumnInk.goal, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 14, height: 2) }
            item(kind == .night ? "Started" : "Woke") { Rectangle().fill(Color.primary).frame(width: 12, height: 2) }
            if kind == .morning {
                item("Until start") { Rectangle().fill(MorningColumnInk.lag).frame(width: 2, height: 12) }
            }
            item("Routine") { Rectangle().fill(tint).frame(width: 10, height: 12) }
        }
        .accessibilityHidden(true)
    }

    private func item<Mark: View>(_ text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) {
            mark()
            Text(text.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
        }
    }
}
