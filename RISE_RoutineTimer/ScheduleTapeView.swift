//
//  ScheduleTapeView.swift
//  RISE_RoutineTimer
//
//  The run sheet's schedule: a horizontal tape of the whole routine where
//  **width is duration**, scrubbed under a fixed centre playhead. Coffee is a
//  wide plain, the four shower steps are one tight cluster, and you can see
//  the shape of the rest of the morning without reading a number.
//
//  This is the one surface in the app that tracks a finger continuously. A
//  scrubber that snapped would just be broken. The line: the tape moves
//  smoothly, the *readout* snaps — every value it shows is at minute
//  resolution, so it cuts to its next value rather than easing there, which
//  is the same rule the countdown follows.
//

import SwiftUI
import UIKit

struct ScheduleTapeView: View {
    let schedule: [ProjectedStep]
    let now: Date
    let tint: Color
    var horizontalPadding: CGFloat = 22

    /// How far the tape has been scrubbed, in points from its leading edge.
    /// Equal to the x under the playhead, because the content is padded by
    /// exactly half the viewport at each end.
    @State private var offset: CGFloat = 0
    @State private var didCentre = false
    @State private var lastFocus = -1

    private static let nowAnchor = "schedule.tape.now"

    /// 38pt to the minute keeps a 1-minute step legible without making a
    /// 44-minute routine an unscrollable mile.
    private let pointsPerMinute: CGFloat = 38
    private let minimumBand: CGFloat = 26
    private let tapeHeight: CGFloat = 60
    private let rulerHeight: CGFloat = 20

    private var pointsPerSecond: CGFloat { pointsPerMinute / 60 }

    // MARK: - Geometry

    private struct Band: Identifiable {
        let step: ProjectedStep
        let x: CGFloat
        let width: CGFloat
        var id: UUID { step.id }
    }

    private var bands: [Band] {
        var out: [Band] = []
        var x: CGFloat = 0
        for step in schedule {
            let w = max(minimumBand, CGFloat(step.seconds) * pointsPerSecond)
            out.append(Band(step: step, x: x, width: w))
            x += w
        }
        return out
    }

    private var totalWidth: CGFloat { bands.last.map { $0.x + $0.width } ?? 0 }

    /// Points are not linear in time — a very short step is floored at
    /// `minimumBand` — so both conversions walk the bands.
    private func time(atX x: CGFloat) -> Date {
        guard let first = bands.first, let last = bands.last else { return now }
        if x <= 0 { return first.step.start }
        for band in bands where x < band.x + band.width {
            let f = Double(max(0, min(1, (x - band.x) / band.width)))
            let span = band.step.end.timeIntervalSince(band.step.start)
            return band.step.start.addingTimeInterval(span * f)
        }
        return last.step.end
    }

    private func x(atTime t: Date) -> CGFloat {
        guard let first = bands.first else { return 0 }
        if t <= first.step.start { return 0 }
        for band in bands where t < band.step.end {
            let span = band.step.end.timeIntervalSince(band.step.start)
            guard span > 0 else { return band.x }
            let f = max(0, min(1, t.timeIntervalSince(band.step.start) / span))
            return band.x + band.width * CGFloat(f)
        }
        return totalWidth
    }

    private func index(atX x: CGFloat) -> Int {
        for (i, band) in bands.enumerated() where x < band.x + band.width { return i }
        return max(0, bands.count - 1)
    }

    private var focused: ProjectedStep? {
        let i = index(atX: offset)
        return schedule.indices.contains(i) ? schedule[i] : nil
    }

    private var playhead: Date { time(atX: offset) }

    /// Far enough from now that offering a way back is worth the pixels.
    private var isScrubbedAway: Bool { abs(playhead.timeIntervalSince(now)) > 45 }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    readout
                    if isScrubbedAway { nowButton(proxy) }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 12)

                // The viewport width comes from a GeometryReader, not a
                // preference: the content needs it *during* layout to pad
                // itself by half a screen at each end, and a preference
                // arrives a pass too late — the tape then opens at step one
                // instead of at now.
                GeometryReader { geo in
                    scroller(viewport: geo.size.width, originX: geo.frame(in: .global).minX)
                        .overlay(alignment: .top) { playheadMark }
                        .overlay { edgeFade }
                }
                .frame(height: tapeHeight + rulerHeight)
            }
            .onAppear {
                guard !didCentre else { return }
                didCentre = true
                DispatchQueue.main.async {
                    proxy.scrollTo(Self.nowAnchor, anchor: .center)
                }
            }
        }
    }

    /// One notch of the scrubber: the readout follows the tape, and crossing
    /// into a new step ticks under the thumb the way a picker does.
    private func scrubbed(to value: CGFloat) {
        offset = value
        let i = index(atX: value)
        guard i != lastFocus else { return }
        if lastFocus >= 0 { UISelectionFeedbackGenerator().selectionChanged() }
        lastFocus = i
    }

    private func nowButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(Self.nowAnchor, anchor: .center)
            }
        } label: {
            Text("NOW")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel("Back to now")
    }

    // MARK: - Readout

    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(Self.clock(playhead))
                        .font(analogFont(30))
                        .tracking(1)
                        .monospacedDigit()
                    Text(relativeText)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(tint)
                }
                Text((focused?.title ?? "").uppercased())
                    .font(analogFont(14))
                    .tracking(1.4)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 3)
                Text(metaText)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var relativeText: String {
        let delta = Int(playhead.timeIntervalSince(now).rounded() / 60)
        if delta <= -1 { return "DONE" }
        if delta <= 0 { return "NOW" }
        return "IN \(delta) MIN"
    }

    private var metaText: String {
        guard let step = focused else { return "" }
        let kind = step.autoNext ? "AUTO" : "MANUAL"
        switch step.state {
        case .done:
            return "TOOK \(TimeFormatting.clockTime(from: step.seconds)) · ENDED \(Self.clock(step.end))"
        case .current, .upcoming:
            return "ENDS \(Self.clock(step.end)) · \(TimeFormatting.clockTime(from: step.plannedSeconds)) · \(kind)"
        }
    }

    // MARK: - Tape

    private func scroller(viewport: CGFloat, originX: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(bands) { band in
                        bandView(band)
                    }
                }
                .frame(height: tapeHeight)

                ruler
                    .frame(width: totalWidth, height: rulerHeight)
            }
            .padding(.horizontal, viewport / 2)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global).minX, initial: true) { _, minX in
                            scrubbed(to: originX - minX)
                        }
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schedule")
        .accessibilityValue(
            "\(focused?.title ?? "") \(relativeText.lowercased()), \(metaText.lowercased())"
        )
    }

    private func bandView(_ band: Band) -> some View {
        let step = band.step
        let isCurrent = step.state == .current

        return ZStack {
            Rectangle()
                .fill(isCurrent ? tint.opacity(0.09) : Color.clear)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(spacing: 2) {
                if band.width >= 22, !step.icon.isEmpty {
                    Text(step.icon).font(.system(size: 15))
                }
                if band.width >= 58 {
                    Text(TimeFormatting.clockTime(from: step.plannedSeconds))
                        .font(.system(size: 8, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: band.width)
        .opacity(step.state == .done ? 0.32 : 1)
        .overlay {
            // The anchor the "NOW" button and the opening scroll centre on.
            // It sits inside the current band at however much of it has gone,
            // held in place by a spacer rather than padding: padding applied
            // after `.id()` becomes part of the identified view, and scrollTo
            // would centre that whole box instead of this 1pt marker.
            if isCurrent {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: min(band.width, max(0, x(atTime: now) - band.x)))
                    Color.clear
                        .frame(width: 1)
                        .id(Self.nowAnchor)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var ruler: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.self) { date in
                let isLabelled = Calendar.current.component(.minute, from: date) % 5 == 0
                let position = x(atTime: date)

                Rectangle()
                    .fill(Color.primary.opacity(isLabelled ? 0.22 : 0.11))
                    .frame(width: 1, height: isLabelled ? 7 : 4)
                    .offset(x: position)

                if isLabelled {
                    Text(Self.clock(date))
                        .font(.system(size: 8, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .offset(x: position + 3, y: 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// One tick a minute, on the minute, for the length of the run.
    private var ticks: [Date] {
        guard let first = schedule.first, let last = schedule.last else { return [] }
        let calendar = Calendar.current
        guard var t = calendar.nextDate(
            after: first.start.addingTimeInterval(-60),
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) else { return [] }

        var out: [Date] = []
        while t <= last.end, out.count < 240 {
            if t >= first.start { out.append(t) }
            t = t.addingTimeInterval(60)
        }
        return out
    }

    private var playheadMark: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(tint)
                .frame(width: 1.5, height: tapeHeight)
            Triangle()
                .fill(tint)
                .frame(width: 9, height: 5)
        }
        .allowsHitTesting(false)
    }

    /// The tape bleeds to both edges, so it needs to fade out rather than be
    /// chopped off — otherwise a half-glyph sits against the sheet's border.
    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemBackground).opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 26)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 26)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Formatting

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    private static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }
}

// MARK: - Plumbing

private struct Triangle: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
