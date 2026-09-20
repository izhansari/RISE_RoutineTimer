//
//  DesignLab.swift
//  RISE_RoutineTimer
//
//  THROWAWAY. Tappable mockups for the History and Today redesign, reached
//  from Settings › Developer › Design Mockups, so the directions can be
//  judged on a phone in the hand rather than in a picture.
//
//  Nothing here is wired to the app: the thirteen mornings are hardcoded
//  (the owner's real Sep 7–19, with an ASSUMED 11:00 wake goal), the states
//  are switched by hand with a picker, and none of it is tested. When a
//  direction is chosen it gets built properly against `MorningMetrics`, and
//  this file is deleted. DEBUG only, so it never ships.
//

#if DEBUG

import SwiftUI
import UIKit

// MARK: - Mock data

private struct LabMorning: Identifiable, Equatable {
    let weekday: String
    let day: Int
    /// Minutes after midnight.
    let wake: Int
    let start: Int
    /// Minutes of routine.
    let routine: Int

    var id: Int { day }
    var lag: Int { start - wake }
    var isWeekend: Bool { weekday == "SAT" || weekday == "SUN" }
}

private enum Lab {
    static let goal = 660   // 11:00 AM — assumed

    static let mornings: [LabMorning] = [
        .init(weekday: "MON", day: 7, wake: 800, start: 800, routine: 38),
        .init(weekday: "TUE", day: 8, wake: 787, start: 819, routine: 26),
        .init(weekday: "WED", day: 9, wake: 768, start: 853, routine: 41),
        .init(weekday: "THU", day: 10, wake: 746, start: 793, routine: 27),
        .init(weekday: "FRI", day: 11, wake: 693, start: 698, routine: 31),
        .init(weekday: "SAT", day: 12, wake: 682, start: 696, routine: 23),
        .init(weekday: "SUN", day: 13, wake: 692, start: 698, routine: 21),
        .init(weekday: "MON", day: 14, wake: 755, start: 800, routine: 34),
        .init(weekday: "TUE", day: 15, wake: 679, start: 718, routine: 28),
        .init(weekday: "WED", day: 16, wake: 638, start: 669, routine: 33),
        .init(weekday: "THU", day: 17, wake: 616, start: 674, routine: 17),
        .init(weekday: "FRI", day: 18, wake: 710, start: 750, routine: 32),
        .init(weekday: "SAT", day: 19, wake: 712, start: 760, routine: 24),
    ]

    /// Today in the Today mockups: Sat Sep 19.
    static let today = mornings[12]
    /// The seven mornings before it, averaged.
    static let usualSnooze = 22, usualLag = 33, usualRoutine = 27

    static let amber = Color(hex: 0xE8890A)
    static let amberText = Color(hex: 0x9A5600)
    static let lagGrey = Color(hex: 0x9B9B9B)

    static func clock(_ minutes: Int, meridiem: Bool = false) -> String {
        let h = minutes / 60, m = minutes % 60
        let text = "\((h + 11) % 12 + 1):" + String(format: "%02d", m)
        return meridiem ? text + (h < 12 ? " AM" : " PM") : text
    }

    static func span(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60):" + String(format: "%02d", minutes % 60) : "\(minutes) MIN"
    }

    static func median(_ values: [Int]) -> Int {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : Int((Double(s[s.count / 2 - 1] + s[s.count / 2]) / 2).rounded())
    }
}

// MARK: - Index

struct DesignLabView: View {
    var body: some View {
        List {
            Section {
                NavigationLink("A · Morning strips") { HistoryStripsLab() }
                NavigationLink("B · Linked tracks") { HistoryTracksLab() }
                NavigationLink("C · Split by a question") { HistorySplitLab() }
                NavigationLink("D · Upright strips (A's marks in B's layout)") { HistoryUprightLab() }
            } header: {
                Text("History")
            } footer: {
                Text("What goes with what: wake time, time to start, routine length — on the same day.")
            }

            Section {
                NavigationLink("A · One bar") { TodayBarLab() }
                NavigationLink("B · Receipt") { TodayReceiptLab() }
                NavigationLink("C · One number at a time") { TodayOneNumberLab() }
                NavigationLink("D · Growing column") { TodayColumnLab() }
                NavigationLink("E · One page, budgets in context") { TodayOnePageLab() }
            } header: {
                Text("Today")
            } footer: {
                Text("One morning, read at a glance. Use the picker at the top of each to step through the morning's states. E is the newest: everything on one screen, History as a link, and both budgets on screen with the one you're spending showing it.")
            }

            Section {
                Text("Prototypes only. The data is your real Sep 7–19 typed in by hand, with an assumed 11:00 AM wake goal. Tap ⓘ on any mockup for what it's good and bad at.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Design Mockups")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared chrome

private struct LabNotes {
    let title: String
    let idea: String
    let pros: [String]
    let cons: [String]
    let take: String
}

/// A mockup's page: white ground, the app's margins, and the ⓘ button.
private struct LabScreen<Content: View>: View {
    let notes: LabNotes
    @ViewBuilder let content: Content
    @State private var showingNotes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
        .background(Color(.systemBackground))
        .navigationTitle(notes.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNotes = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Pros and cons")
            }
        }
        .sheet(isPresented: $showingNotes) { LabNotesSheet(notes: notes) }
    }
}

private struct LabNotesSheet: View {
    let notes: LabNotes

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ReceiptSheetTitle(title: notes.title)
                    .padding(.top, 26)
                block("The idea", [notes.idea], mark: nil)
                block("Good at", notes.pros, mark: "+")
                block("Weak at", notes.cons, mark: "−")
                block("My take", [notes.take], mark: nil)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    private func block(_ title: String, _ lines: [String], mark: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabLabel(title)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let mark {
                        Text(mark).font(analogFont(15)).frame(width: 12)
                    }
                    Text(line).font(.system(size: 15)).lineSpacing(3)
                }
            }
        }
    }
}

private struct LabLabel: View {
    let text: String
    var color: Color = .secondary
    var size: CGFloat = 10
    init(_ text: String, color: Color = .secondary, size: CGFloat = 10) {
        self.text = text; self.color = color; self.size = size
    }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

private struct LabStat: View {
    let label: String
    let value: String
    var color: Color = .primary
    var size: CGFloat = 17
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabLabel(label, color: Color(.tertiaryLabel), size: 9)
            Text(value).font(analogFont(size)).monospacedDigit().foregroundStyle(color)
                .contentTransition(.identity)
        }
    }
}

private var labTint: Color {
    let raw = UserDefaults.standard.string(forKey: FillTheme.storageKey) ?? FillTheme.default.rawValue
    return (FillTheme(rawValue: raw) ?? .default).color
}

private var labBox: some View {
    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
}

private struct LabHatch: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 5
        }
        return path
    }
}

// MARK: - History A · Morning strips

private struct HistoryStripsLab: View {
    enum Sort: String, CaseIterable { case date = "Date", wake = "Wake", lag = "To start", length = "Length" }

    @State private var sort = Sort.date
    @State private var selected: Int? = 9

    private let t0 = 600.0, t1 = 900.0   // 10 AM – 3 PM

    private var rows: [LabMorning] {
        switch sort {
        case .date: return Lab.mornings.reversed()
        case .wake: return Lab.mornings.sorted { $0.wake < $1.wake }
        case .lag: return Lab.mornings.sorted { $0.lag < $1.lag }
        case .length: return Lab.mornings.sorted { $0.routine < $1.routine }
        }
    }

    var body: some View {
        LabScreen(notes: LabNotes(
            title: "Morning strips",
            idea: "Every morning is one row on a shared clock: a tick where you woke, a thin line until you started, a bar for the routine. Sorting is the analysis — sort by wake time and see whether the lines and bars change as you go down.",
            pros: [
                "Wake, time to start and routine length are on the same row, so their relationship is visible at all.",
                "Replaces three charts AND the sessions list: tap a row to open that run.",
                "A missed day is simply an empty row — no separate counter needed.",
                "Same picture as one morning on Today, repeated — one visual language.",
            ],
            cons: [
                "Shows you a pattern but never states it; you have to read it yourself.",
                "Thirty rows is a long scroll; needs a 2-week default.",
                "Weak on the long trend (am I better than a month ago?) — that needs a line somewhere.",
            ],
            take: "Best single replacement for the page. Pair it with the sentence card up top, which links to the Split view for proof."
        )) {
            insight
            VStack(alignment: .leading, spacing: 8) {
                LabLabel("Sort mornings by")
                Picker("Sort", selection: $sort.animation(.snappy(duration: 0.35))) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            strips
            legend
            HStack(spacing: 0) {
                LabStat(label: "Typical wake", value: "11:50").frame(maxWidth: .infinity, alignment: .leading).padding(12)
                LabStat(label: "To start", value: "39 MIN").frame(maxWidth: .infinity, alignment: .leading).padding(12)
                LabStat(label: "Routine", value: "28 MIN").frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .overlay(labBox)
        }
    }

    private var insight: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabLabel("What these 13 mornings say")
            Text("On your earlier mornings the routine runs about **6 min shorter**. Time to start is mixed: usually quicker, but your two earliest days were slow off the mark.")
                .font(.system(size: 16)).lineSpacing(3)
            NavigationLink { HistorySplitLab() } label: {
                LabLabel("Compare earlier and later ›", color: .primary)
            }
        }
        .padding(14)
        .overlay(labBox)
    }

    private var strips: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 50, height: 14)
                GeometryReader { geo in
                    ForEach(Array(stride(from: 600, through: 900, by: 60)), id: \.self) { tick in
                        Text("\((tick / 60 + 11) % 12 + 1)\(tick < 720 ? "AM" : "PM")")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .position(x: x(Double(tick), geo.size.width), y: 7)
                    }
                }
                .frame(height: 14)
                Color.clear.frame(width: 34, height: 14)
            }
            // The rows are inset by this much for their highlight.
            .padding(.horizontal, 6)

            ForEach(rows) { morning in
                row(morning)
            }
        }
    }

    private func x(_ minutes: Double, _ width: CGFloat) -> CGFloat {
        CGFloat((minutes - t0) / (t1 - t0)) * width
    }

    private func row(_ m: LabMorning) -> some View {
        let isSelected = selected == m.id
        let tint = labTint

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("\(m.weekday) \(m.day)")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 50, alignment: .leading)

                Canvas { context, size in
                    let mid = size.height / 2
                    // Goal, dashed, through every row.
                    var goal = Path()
                    goal.move(to: CGPoint(x: x(Double(Lab.goal), size.width), y: 0))
                    goal.addLine(to: CGPoint(x: x(Double(Lab.goal), size.width), y: size.height))
                    context.stroke(goal, with: .color(Lab.amber), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))

                    let wakeX = x(Double(m.wake), size.width)
                    let startX = x(Double(m.start), size.width)
                    let endX = x(Double(m.start + m.routine), size.width)
                    context.fill(Path(CGRect(x: wakeX, y: mid - 1, width: max(0, startX - wakeX), height: 2)), with: .color(Lab.lagGrey))
                    context.fill(Path(CGRect(x: wakeX - 1, y: mid - 8, width: 2, height: 16)), with: .color(.primary))
                    context.fill(Path(CGRect(x: startX, y: mid - 6, width: endX - startX, height: 12)), with: .color(tint))
                }
                .frame(height: 32)

                Text("\(m.routine)")
                    .font(analogFont(14)).monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }

            if isSelected {
                HStack(spacing: 12) {
                    LabStat(label: "Woke", value: Lab.clock(m.wake), size: 15)
                    LabStat(label: "To start", value: Lab.span(m.lag), size: 15)
                    LabStat(label: "Routine", value: "\(m.routine) MIN", color: tint, size: 15)
                    Spacer(minLength: 4)
                    LabLabel("Open ›", color: .primary).fixedSize()
                }
                .padding(.leading, 50)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .background(isSelected ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.28)) { selected = isSelected ? nil : m.id }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Rectangle().fill(Lab.amber).frame(width: 1.5, height: 12)
                LabLabel("Goal", color: Color(.tertiaryLabel), size: 9)
            }
            HStack(spacing: 5) {
                Rectangle().fill(Color.primary).frame(width: 2, height: 12)
                LabLabel("Woke", color: Color(.tertiaryLabel), size: 9)
            }
            HStack(spacing: 5) {
                Rectangle().fill(Lab.lagGrey).frame(width: 16, height: 2)
                LabLabel("Until start", color: Color(.tertiaryLabel), size: 9)
            }
            HStack(spacing: 5) {
                Rectangle().fill(labTint).frame(width: 16, height: 10)
                LabLabel("Routine", color: Color(.tertiaryLabel), size: 9)
            }
        }
    }
}

// MARK: - History B · Linked tracks

private struct HistoryTracksLab: View {
    @State private var index: Int? = 2

    private var shown: LabMorning? { index.map { Lab.mornings[$0] } }

    var body: some View {
        let tint = labTint
        LabScreen(notes: LabNotes(
            title: "Linked tracks",
            idea: "Today's three charts, stacked on one day axis with one cursor. Drag across and wake, time to start and routine all read out for the same morning.",
            pros: [
                "Smallest change from what exists — same charts, finally aligned.",
                "Keeps the time trend visible, which the strips are weak at.",
                "One readout instead of three.",
            ],
            cons: [
                "You still compare three shapes by eye; relationships are implied, never shown.",
                "Doesn't replace the sessions list.",
                "Dragging inside a scrolling page fights the scroll (this prototype has that problem too).",
            ],
            take: "The safe option, and the least revealing. Worth it only if the strips feel too unfamiliar."
        )) {
            readout
            GeometryReader { geo in
                let step = (geo.size.width - 16) / CGFloat(Lab.mornings.count - 1)
                VStack(spacing: 0) {
                    track("Woke", "typical 11:50 AM", height: 84) { i, size in
                        let m = Lab.mornings[i]
                        let y = CGFloat(m.wake - 600) / 240 * size.height
                        let r: CGFloat = i == index ? 5 : 3.5
                        return (Path(ellipseIn: CGRect(x: 8 + CGFloat(i) * step - r, y: y - r, width: r * 2, height: r * 2)), Color.primary)
                    }
                    track("Time to start", "typical 39 min", height: 70) { i, size in
                        let h = max(2, CGFloat(Lab.mornings[i].lag) / 90 * size.height)
                        return (Path(CGRect(x: 8 + CGFloat(i) * step - 6, y: size.height - h, width: 12, height: h)),
                                i == index ? Color.primary : Lab.lagGrey)
                    }
                    track("Routine", "typical 28 min", height: 70) { i, size in
                        let h = CGFloat(Lab.mornings[i].routine) / 45 * size.height
                        return (Path(CGRect(x: 8 + CGFloat(i) * step - 6, y: size.height - h, width: 12, height: h)),
                                tint.opacity(i == index ? 1 : 0.3))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let index {
                        Rectangle().fill(Color.primary).frame(width: 1.5)
                            .offset(x: 8 + CGFloat(index) * step - 0.75)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let i = Int(((value.location.x - 8) / step).rounded())
                            let clamped = min(max(i, 0), Lab.mornings.count - 1)
                            if clamped != index {
                                UISelectionFeedbackGenerator().selectionChanged()
                                index = clamped
                            }
                        }
                )
            }
            .frame(height: 84 + 70 + 70 + 3 * 34)

            Text("One finger, one day, three answers.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LabLabel(shown.map { "\($0.weekday), SEP \($0.day)" } ?? "Typical morning", color: .primary, size: 11)
                Spacer()
                LabLabel("Open run ›", color: .primary)
            }
            HStack(spacing: 18) {
                LabStat(label: "Woke", value: shown.map { Lab.clock($0.wake) } ?? "11:50", size: 22)
                LabStat(label: "To start", value: shown.map { Lab.span($0.lag) } ?? "39 MIN", size: 22)
                LabStat(label: "Routine", value: "\(shown?.routine ?? 28) MIN", color: labTint, size: 22)
            }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary, lineWidth: 1.5))
        .transaction { $0.animation = nil }
    }

    private func track(
        _ title: String, _ typical: String, height: CGFloat,
        mark: @escaping (Int, CGSize) -> (Path, Color)
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
            HStack {
                LabLabel(title)
                Spacer()
                LabLabel(typical, color: Color(.tertiaryLabel), size: 9)
            }
            Canvas { context, size in
                for i in Lab.mornings.indices {
                    let (path, color) = mark(i, size)
                    context.fill(path, with: .color(color))
                }
            }
            .frame(height: height)
        }
        .frame(height: height + 34, alignment: .top)
    }
}

// MARK: - History C · Split by a question

private struct HistorySplitLab: View {
    enum Split: String, CaseIterable { case wake = "Wake time", weekday = "Weekday", lag = "Time to start" }

    @State private var split = Split.wake

    private var groups: (a: [LabMorning], b: [LabMorning], aName: String, bName: String) {
        let all = Lab.mornings
        switch split {
        case .wake:
            return (all.filter { $0.wake < 710 }, all.filter { $0.wake >= 710 }, "Earlier · before 11:50", "Later · 11:50 and after")
        case .weekday:
            return (all.filter { !$0.isWeekend }, all.filter(\.isWeekend), "Weekdays", "Weekends")
        case .lag:
            return (all.filter { $0.lag < 39 }, all.filter { $0.lag >= 39 }, "Quick starts · under 39 min", "Slow starts · 39 min and over")
        }
    }

    var body: some View {
        let g = groups
        LabScreen(notes: LabNotes(
            title: "Split by a question",
            idea: "Pick what to split your mornings by; get the two groups side by side with a sentence on top. Every dot is one morning, so you can see when a difference isn't real yet.",
            pros: [
                "Answers \"what happens on days I wake earlier?\" directly, in words and numbers.",
                "The dots keep it honest — overlapping groups mean don't trust the headline.",
                "New splits are cheap to add (skipped steps, target met, weekday).",
            ],
            cons: [
                "No time axis: can't see trend, and can't open a specific day.",
                "Thin with under ~2 weeks of data.",
                "It's a tool, not a landing page — nobody opens History to operate a picker.",
            ],
            take: "Not the page itself — the drill-down behind the sentence on the Strips page. That pairing is my recommendation."
        )) {
            VStack(alignment: .leading, spacing: 8) {
                LabLabel("Split my mornings by")
                Picker("Split", selection: $split) {
                    ForEach(Split.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                groupKey(g.aName, count: g.a.count, color: labTint)
                groupKey(g.bName, count: g.b.count, color: .primary)
            }

            Text(sentence(g.a, g.b))
                .font(.system(size: 17, weight: .medium)).lineSpacing(3)

            VStack(spacing: 0) {
                metric("Woke", g.a.map(\.wake), g.b.map(\.wake), range: 600...840) { Lab.clock($0) }
                metric("Time to start", g.a.map(\.lag), g.b.map(\.lag), range: 0...90) { "\($0) MIN" }
                metric("Routine", g.a.map(\.routine), g.b.map(\.routine), range: 15...45) { "\($0) MIN" }
            }

            Text("Big numbers are medians. Every dot is one morning; the tall tick is the median. Overlapping dots mean the difference isn't reliable yet.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(2)
        }
    }

    private func groupKey(_ name: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(name).font(.system(size: 12, weight: .semibold))
            Text("· \(count) mornings").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func sentence(_ a: [LabMorning], _ b: [LabMorning]) -> String {
        let routine = Lab.median(a.map(\.routine)) - Lab.median(b.map(\.routine))
        let lag = Lab.median(a.map(\.lag)) - Lab.median(b.map(\.lag))
        func phrase(_ delta: Int, _ shorter: String, _ longer: String) -> String {
            abs(delta) < 3 ? "about the same" : "\(abs(delta)) min \(delta < 0 ? shorter : longer)"
        }
        let first: String
        switch split {
        case .wake: first = "When you're up earlier"
        case .weekday: first = "On weekdays"
        case .lag: first = "When you start quickly"
        }
        return "\(first), the routine is \(phrase(routine, "shorter", "longer")) and you take \(phrase(lag, "less", "longer")) to get going."
    }

    private func metric(_ title: String, _ a: [Int], _ b: [Int], range: ClosedRange<Int>, format: @escaping (Int) -> String) -> some View {
        let tint = labTint
        return VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Color.primary).frame(height: 1.5)
            LabLabel(title)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(format(Lab.median(a))).font(analogFont(26)).foregroundStyle(tint)
                LabLabel("vs", color: Color(.tertiaryLabel))
                Text(format(Lab.median(b))).font(analogFont(26))
            }
            .contentTransition(.identity)

            Canvas { context, size in
                func px(_ v: Int) -> CGFloat {
                    7 + CGFloat(v - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound) * (size.width - 14)
                }
                for (row, values, color) in [(0, a, tint), (1, b, Color.primary)] {
                    let y = CGFloat(row) * 18 + 9
                    for v in values {
                        context.fill(Path(ellipseIn: CGRect(x: px(v) - 4.5, y: y - 4.5, width: 9, height: 9)), with: .color(color.opacity(0.8)))
                    }
                    context.fill(Path(CGRect(x: px(Lab.median(values)) - 1, y: y - 9, width: 2, height: 18)), with: .color(color))
                }
            }
            .frame(height: 36)

            HStack {
                LabLabel(format(range.lowerBound), color: Color(.tertiaryLabel), size: 9)
                Spacer()
                LabLabel(format(range.upperBound), color: Color(.tertiaryLabel), size: 9)
            }
        }
        .padding(.bottom, 16)
        .animation(.snappy(duration: 0.3), value: split)
    }
}

// MARK: - Today, shared

private enum LabStage: String, CaseIterable { case inBed = "In bed", up = "Up", done = "Done" }

private struct LabStagePicker: View {
    @Binding var stage: LabStage
    var stages: [LabStage] = LabStage.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabLabel("Prototype · pretend it's…", color: Color(.tertiaryLabel), size: 9)
            Picker("Stage", selection: $stage) {
                ForEach(stages, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct LabCTA: View {
    let title: String
    var body: some View {
        Text(title)
            .font(analogFont(20)).tracking(3)
            .foregroundStyle(Color(.systemBackground))
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// A counter that ticks up from a starting value while the mockup is open,
/// so the live states feel live.
private struct LabTicker<Content: View>: View {
    let from: Int
    @ViewBuilder let content: (String) -> Content
    @State private var opened = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = from + Int(context.date.timeIntervalSince(opened))
            content("\(total / 60):" + String(format: "%02d", total % 60))
        }
    }
}

// MARK: - Today A · One bar

private struct TodayBarLab: View {
    @State private var stage = LabStage.done
    private let t = Lab.today

    var body: some View {
        let snooze = t.wake - Lab.goal
        LabScreen(notes: LabNotes(
            title: "One bar",
            idea: "The morning is one bar in three segments — snooze, time to start, routine — widths proportional to minutes, with your usual morning as a ghost bar underneath at the same scale.",
            pros: [
                "Replaces the timeline AND the three tiles: one object instead of two saying the same thing.",
                "A slow start is visibly a fat segment; no colour code to learn.",
                "Nothing can overlap — the dots' collision problem disappears.",
                "\"Versus usual\" is a shape you see, not a caption you read.",
            ],
            cons: [
                "A very short segment (woke 2 min late) gets too thin to label — needs a minimum width.",
                "Less literal than a clock; the times move to small print at the joins.",
                "Before you're awake there's barely a bar to draw.",
            ],
            take: "My pick for the finished morning. Use One number for the two states before the routine."
        )) {
            LabStagePicker(stage: $stage)

            VStack(alignment: .leading, spacing: 10) {
                LabLabel(stage == .done ? "This morning, minutes" : "This morning, so far")
                bar(snooze: snooze)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    LabLabel("Your usual, last 7")
                    Spacer()
                    LabLabel("\(Lab.usualSnooze) · \(Lab.usualLag) · \(Lab.usualRoutine)", color: Color(.tertiaryLabel), size: 9)
                }
                segments([(Lab.usualSnooze, .hatch), (Lab.usualLag, .fill(Lab.lagGrey)), (Lab.usualRoutine, .fill(labTint))], total: 124, height: 10)
                    .opacity(0.55)
            }

            Group {
                switch stage {
                case .inBed:
                    Text("You're usually up by **11:22**.")
                case .up:
                    Text("You usually start **33 min** after waking. That's two minutes from now.")
                case .done:
                    Text("Up **30 min later** than usual and **15 slower** to start. The routine itself was 3 min quicker.")
                }
            }
            .font(.system(size: 17, weight: .medium)).lineSpacing(3)

            switch stage {
            case .inBed: LabCTA(title: "I'M AWAKE")
            case .up: LabCTA(title: "START ROUTINE")
            case .done:
                HStack {
                    LabLabel("Morning logged")
                    Spacer()
                    LabLabel("Fix a time ›", color: .primary)
                }
            }
        }
    }

    private enum Fill { case hatch, fill(Color), outline(Color) }

    @ViewBuilder
    private func bar(snooze: Int) -> some View {
        switch stage {
        case .inBed:
            LabTicker(from: 23 * 60 + 10) { text in
                LabStat(label: "Past your 11:00 goal", value: "+" + text, color: Lab.amberText, size: 24)
            }
            segments([(23, .hatch), (101, .outline(Color.primary.opacity(0.2)))], total: 124, height: 26)
            joints([(0, "Goal", "11:00"), (23, "Now", "11:23")], total: 124)
        case .up:
            HStack(alignment: .top, spacing: 0) {
                LabStat(label: "Snooze", value: "\(snooze)", size: 24).frame(width: 120, alignment: .leading)
                LabTicker(from: 31 * 60 + 7) { text in
                    LabStat(label: "Since you woke", value: text, color: Lab.amberText, size: 24)
                }
            }
            segments([(snooze, .hatch), (31, .fill(Lab.amber)), (41, .outline(labTint))], total: 124, height: 26)
            joints([(0, "Goal", "11:00"), (snooze, "Woke", "11:52"), (snooze + 31, "Now", "12:23")], total: 124)
        case .done:
            HStack(alignment: .top, spacing: 0) {
                LabStat(label: "Snooze", value: "\(snooze)", size: 24).frame(maxWidth: .infinity, alignment: .leading)
                LabStat(label: "To start", value: "\(t.lag)", size: 24).frame(maxWidth: .infinity, alignment: .leading)
                LabStat(label: "Routine", value: "\(t.routine)", color: labTint, size: 24).frame(maxWidth: .infinity, alignment: .leading)
            }
            segments([(snooze, .hatch), (t.lag, .fill(Lab.lagGrey)), (t.routine, .fill(labTint))], total: 124, height: 26)
            joints([(0, "Goal", "11:00"), (snooze, "Woke", "11:52"), (snooze + t.lag, "Started", "12:40"), (124, "Done", "1:04")], total: 124)
        }
    }

    private func segments(_ parts: [(Int, Fill)], total: Int, height: CGFloat) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    let width = geo.size.width * CGFloat(part.0) / CGFloat(total)
                    Group {
                        switch part.1 {
                        case .hatch:
                            LabHatch().stroke(Lab.lagGrey, lineWidth: 1.2).clipped()
                                .overlay(Rectangle().strokeBorder(Lab.lagGrey, lineWidth: 1))
                        case .fill(let color):
                            Rectangle().fill(color)
                        case .outline(let color):
                            Rectangle().strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                    .frame(width: width, height: height)
                }
            }
        }
        .frame(height: height)
    }

    /// Clock times at the joins. Clamped at the ends so the first and last
    /// labels stay on the screen.
    private func joints(_ items: [(Int, String, String)], total: Int) -> some View {
        GeometryReader { geo in
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let x = geo.size.width * CGFloat(item.0) / CGFloat(total)
                VStack(spacing: 2) {
                    Rectangle().fill(Color.primary).frame(width: 1.5, height: 8)
                    LabLabel(item.1, color: Color(.tertiaryLabel), size: 8)
                    Text(item.2).font(.system(size: 11, weight: .semibold))
                }
                .fixedSize()
                .position(x: min(max(x, 20), geo.size.width - 20), y: 20)
            }
        }
        .frame(height: 40)
    }
}

// MARK: - Today B · Receipt

private struct TodayReceiptLab: View {
    @State private var stage = LabStage.done

    var body: some View {
        LabScreen(notes: LabNotes(
            title: "Receipt",
            idea: "The morning as an itemised receipt: goal, woke, started, done, with the duration between each pair of lines and your usual figure beside it.",
            pros: [
                "The most on-brand of the three — it IS a receipt.",
                "Rows can't collide, whatever the times are.",
                "Exact: every clock time and every duration, in reading order.",
                "Totals line (goal → done) gives one number for the whole morning.",
            ],
            cons: [
                "It's a table. You read it; you don't see it. No at-a-glance shape.",
                "Tallest option — pushes budgets and the button down the screen.",
                "\"Versus usual\" is another column of numbers to parse.",
            ],
            take: "The fallback if the bar feels too chart-like. Also a good candidate for a share / end-of-morning card."
        )) {
            LabStagePicker(stage: $stage, stages: [.up, .done])

            VStack(spacing: 0) {
                HStack {
                    LabLabel("This morning")
                    Spacer()
                    LabLabel("vs your usual", color: Color(.tertiaryLabel), size: 9)
                }
                .padding(.bottom, 8)
                dashed
                line("Goal", "11:00 AM")
                gap("52 MIN SNOOZE", "usual 22", Lab.amberText)
                line("Woke", "11:52 AM")
                if stage == .done {
                    gap("48 MIN TO START", "usual 33", Lab.amberText)
                    line("Started", "12:40 PM")
                    gap("24 MIN ROUTINE", "usual 27", labTint)
                    line("Done", "1:04 PM")
                    dashed
                    line("Goal to done", "2:04", note: "usual 1:22", size: 22)
                } else {
                    LabTicker(from: 31 * 60 + 7) { text in
                        gap("\(text) AND COUNTING", "usual 33", Lab.amberText)
                    }
                    line("Started", "—")
                }
            }
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary, lineWidth: 1.5))

            if stage == .up { LabCTA(title: "START ROUTINE") }
        }
    }

    private var dashed: some View {
        LabHLine().stroke(Color.primary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(height: 2).padding(.vertical, 6)
    }

    private func line(_ label: String, _ value: String, note: String = "", size: CGFloat = 19) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            LabLabel(label).frame(width: 92, alignment: .leading)
            Text(value).font(analogFont(size)).monospacedDigit()
            Spacer()
            Text(note).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func gap(_ text: String, _ usual: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            LabVLine().stroke(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                .frame(width: 2, height: 28)
                .padding(.leading, 40)
            Text(text).font(analogFont(15)).foregroundStyle(color).contentTransition(.identity)
            Spacer()
            Text(usual).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Today C · One number at a time

private struct TodayOneNumberLab: View {
    @State private var stage = LabStage.inBed

    var body: some View {
        LabScreen(notes: LabNotes(
            title: "One number at a time",
            idea: "The screen shows only the number that matters right now. In bed: how far past your goal. Up: how long you've been drifting, with a marker where you usually get going. Everything else waits.",
            pros: [
                "Readable from the pillow with one eye open — which is when this screen is actually used.",
                "The counter creates gentle pressure; the usual-start marker gives it a target.",
                "One button, under the thumb, no hunting.",
                "Closest in spirit to the timer screen: silent until it matters.",
            ],
            cons: [
                "Says nothing about the finished morning — needs another layout for that state.",
                "Hides the weekly budgets and streak below the fold.",
                "A big red-ish number first thing can feel like being told off.",
            ],
            take: "My pick for the two states before the routine. Hand over to One bar once the morning is done."
        )) {
            LabStagePicker(stage: $stage, stages: [.inBed, .up])

            VStack(spacing: 14) {
                switch stage {
                case .inBed:
                    LabLabel("Past your 11:00 goal", color: Lab.amberText, size: 11)
                    LabTicker(from: 23 * 60 + 10) { text in
                        Text("+" + text).font(digitFont(84)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                            .contentTransition(.identity)
                    }
                    Rectangle().fill(Color.primary).frame(width: 132, height: 3)
                    Text("You're usually up by 11:22.").font(.system(size: 15)).foregroundStyle(.secondary)
                default:
                    LabLabel("Since you woke at 11:52", size: 11)
                    LabTicker(from: 31 * 60 + 7) { text in
                        Text(text).font(digitFont(84)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                            .contentTransition(.identity)
                    }
                    Rectangle().fill(Color.primary).frame(width: 132, height: 3)
                    usualMarker.padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)

            LabCTA(title: stage == .inBed ? "I'M AWAKE" : "START ROUTINE")

            LabLabel(stage == .inBed ? "Yesterday · up 11:50 · 40 to start · 32 routine" : "52 min past goal this morning",
                     color: Color(.tertiaryLabel), size: 9)
                .frame(maxWidth: .infinity)
        }
    }

    /// Where you usually get going, on a 0–60 minute line.
    private var usualMarker: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.07))
                    Rectangle().fill(Color.primary).frame(width: geo.size.width * 31 / 60)
                    Rectangle().fill(Lab.amber).frame(width: 2, height: 20)
                        .offset(x: geo.size.width * 33 / 60, y: 0)
                }
            }
            .frame(height: 10)
            HStack {
                LabLabel("0", color: Color(.tertiaryLabel), size: 9)
                Spacer()
                LabLabel("Usual start · 33 min", color: Lab.amberText, size: 9)
                Spacer()
                LabLabel("60", color: Color(.tertiaryLabel), size: 9)
            }
        }
    }
}

// MARK: - The upright glyph (History D, Today D)

private struct LabVLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct LabHLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// One morning stood on end, the clock running down the page: a dotted line
/// from the goal to where you woke (the snooze), a cap at the wake time, a
/// thin whisker until the routine started, and a box for the routine.
///
/// Every part is always in the tree, at zero height until it exists, so a
/// morning that is still happening *grows* rather than popping in: whichever
/// part has no end yet runs to `now`.
private struct LabColumn: View {
    let goal: Int
    let wake: Int?
    let start: Int?
    let end: Int?
    var now: Int? = nil
    let range: ClosedRange<Int>
    let height: CGFloat
    let tint: Color
    var faded = false

    private func y(_ minutes: Int) -> CGFloat {
        CGFloat(minutes - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound) * height
    }

    var body: some View {
        let snoozeTo = wake ?? now ?? goal
        let lagTo = start ?? now ?? wake ?? goal
        let boxTo = end ?? now ?? start ?? goal

        ZStack(alignment: .top) {
            LabVLine()
                .stroke(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                .frame(width: 2, height: abs(y(snoozeTo) - y(goal)))
                .offset(y: min(y(goal), y(snoozeTo)))
            Rectangle().fill(Lab.lagGrey)
                .frame(width: 2, height: wake == nil ? 0 : max(0, y(lagTo) - y(wake ?? goal)))
                .offset(y: y(wake ?? snoozeTo))
            Rectangle().fill(Color.primary)
                .frame(width: 14, height: 2)
                .offset(y: y(wake ?? snoozeTo) - 1)
                .opacity(wake == nil ? 0 : 1)
            Rectangle().fill(tint)
                .frame(width: 12, height: start == nil ? 0 : max(0, y(boxTo) - y(start ?? goal)))
                .offset(y: y(start ?? lagTo))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .opacity(faded ? 0.32 : 1)
    }
}

/// Hour lines and the dashed goal line behind a set of columns.
private struct LabClockGrid: View {
    let range: ClosedRange<Int>
    let height: CGFloat

    private func y(_ minutes: Int) -> CGFloat {
        CGFloat(minutes - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound) * height
    }

    private var hours: [Int] {
        Array(stride(from: (range.lowerBound + 59) / 60 * 60, through: range.upperBound, by: 60))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { hour in
                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).offset(y: y(hour))
            }
            LabHLine()
                .stroke(Lab.amber, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(height: 2)
                .offset(y: y(Lab.goal) - 1)
        }
        .frame(height: height, alignment: .top)
    }

    /// The hour labels, for the gutter beside the grid.
    var labels: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(hours, id: \.self) { hour in
                Text("\((hour / 60 + 11) % 12 + 1)\(hour < 720 ? "AM" : "PM")")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(y: y(hour) - 6)
            }
        }
        .frame(width: 34, height: height, alignment: .topTrailing)
    }
}

// MARK: - History D · Upright strips

private struct HistoryUprightLab: View {
    @State private var index: Int? = 2

    private let range = 600...900
    private let height: CGFloat = 300

    private var shown: LabMorning? { index.map { Lab.mornings[$0] } }

    var body: some View {
        let tint = labTint
        LabScreen(notes: LabNotes(
            title: "Upright strips",
            idea: "History B's layout — one day axis, one finger, one readout — but each day is History A's mark stood on end: the clock runs down the page, a cap where you woke, a whisker until you started, a box for the routine.",
            pros: [
                "Keeps B's left-to-right date order, so the trend is readable: are the caps climbing toward the goal line?",
                "Keeps A's point: wake, time to start and routine are one object per day, so you see how they go together.",
                "One chart instead of three, and two weeks fit with no scrolling.",
                "Reads like a calendar day view — time down the page is already familiar.",
                "Today's column can sit at the right-hand end, still growing: the same mark on both tabs (see Today D).",
            ],
            cons: [
                "Width runs out: past ~3 weeks the columns get too thin, so a month means paging or sideways scrolling.",
                "Loses A's sort — and sorting was A's analysis tool. Sorted columns would break the date axis that is the point here.",
                "\"Higher = earlier = better\" has to be learned; the rows in A don't need it.",
                "A sideways drag inside a vertically scrolling page is the same fight as the pie chart — it would need the press-then-drag treatment, or to sit at the top where the page barely scrolls.",
            ],
            take: "Stronger than either parent as the top of the History page. I'd put this first, the sessions list under it, and keep Split (C) behind the insight sentence for the what-goes-with-what proof that sorting gave A."
        )) {
            readout(tint)

            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    LabClockGrid(range: range, height: height).labels
                    GeometryReader { geo in
                        let step = geo.size.width / CGFloat(Lab.mornings.count)
                        ZStack(alignment: .topLeading) {
                            LabClockGrid(range: range, height: height)
                            if let index {
                                Rectangle().fill(Color.primary.opacity(0.06))
                                    .frame(width: step, height: height)
                                    .offset(x: CGFloat(index) * step)
                            }
                            HStack(spacing: 0) {
                                ForEach(Lab.mornings) { m in
                                    LabColumn(goal: Lab.goal, wake: m.wake, start: m.start, end: m.start + m.routine,
                                              range: range, height: height, tint: tint)
                                        .frame(width: step)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0).onChanged { value in
                                let i = min(max(Int(value.location.x / step), 0), Lab.mornings.count - 1)
                                if i != index {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    index = i
                                }
                            }
                        )
                    }
                    .frame(height: height)
                }

                HStack(spacing: 6) {
                    Color.clear.frame(width: 34, height: 12)
                    HStack(spacing: 0) {
                        ForEach(Array(Lab.mornings.enumerated()), id: \.offset) { i, m in
                            Text("\(m.day)")
                                .font(.system(size: 9, weight: i == index ? .bold : .semibold))
                                .foregroundStyle(i == index ? .primary : .tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .transaction { $0.animation = nil }

            uprightLegend(tint)

            Text("Slide a finger across. Earlier is higher, so caps near or above the dashed line are the good mornings.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(2)
        }
    }

    private func readout(_ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LabLabel(shown.map { "\($0.weekday), SEP \($0.day)" } ?? "Typical morning", color: .primary, size: 11)
                Spacer()
                LabLabel("Open run ›", color: .primary)
            }
            HStack(spacing: 18) {
                LabStat(label: "Woke", value: shown.map { Lab.clock($0.wake) } ?? "11:50", size: 22)
                LabStat(label: "To start", value: shown.map { Lab.span($0.lag) } ?? "39 MIN", size: 22)
                LabStat(label: "Routine", value: "\(shown?.routine ?? 28) MIN", color: tint, size: 22)
            }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary, lineWidth: 1.5))
        .transaction { $0.animation = nil }
    }
}

private func uprightLegend(_ tint: Color) -> some View {
    HStack(spacing: 12) {
        HStack(spacing: 5) {
            Rectangle().fill(Lab.amber).frame(width: 14, height: 1.5)
            LabLabel("Goal", color: Color(.tertiaryLabel), size: 9)
        }
        HStack(spacing: 5) {
            Rectangle().fill(Color.primary).frame(width: 12, height: 2)
            LabLabel("Woke", color: Color(.tertiaryLabel), size: 9)
        }
        HStack(spacing: 5) {
            Rectangle().fill(Lab.lagGrey).frame(width: 2, height: 12)
            LabLabel("Until start", color: Color(.tertiaryLabel), size: 9)
        }
        HStack(spacing: 5) {
            Rectangle().fill(tint).frame(width: 10, height: 12)
            LabLabel("Routine", color: Color(.tertiaryLabel), size: 9)
        }
    }
}

// MARK: - Today D · Growing column

private struct TodayColumnLab: View {
    enum Stage: String, CaseIterable { case inBed = "In bed", up = "Up", running = "Running", done = "Done" }

    @State private var stage = Stage.inBed

    private let range = 600...860
    private let height: CGFloat = 290
    /// Sep 12–18, the seven mornings before today.
    private let week = Array(Lab.mornings[5..<12])
    private let t = Lab.today

    private var now: Int? {
        switch stage {
        case .inBed: return 683      // 11:23
        case .up: return 743         // 12:23
        case .running: return 772    // 12:52
        case .done: return nil
        }
    }

    var body: some View {
        let tint = labTint
        LabScreen(notes: LabNotes(
            title: "Growing column",
            idea: "Today is the same upright mark as History D, drawn at the end of your last seven mornings and still growing: a dotted line drops from the goal while you're in bed, the cap lands when you wake, the whisker stretches until you start, and the box fills as the routine runs.",
            pros: [
                "One visual language across Today and History — learn the mark once.",
                "Context for free: today against the week, at a glance, with no \"vs usual\" arithmetic.",
                "The growth is literal and a little motivating: lying in bed visibly lengthens the dotted line.",
                "When the morning ends, this column simply becomes the newest one in History.",
            ],
            cons: [
                "Tall — it takes most of the screen, pushing the button and the budgets down.",
                "In bed, there is almost nothing to look at: a short dotted line. One number (C) does that moment far better.",
                "A thin column is a small stage for the main event; the numbers end up doing the real work underneath.",
                "Slow-moving: over a 30-minute wait the whisker grows a few points. It rewards a glance later, not a stare now.",
            ],
            take: "Lovely as the *finished* state and as a bridge to History. For the two live states before the routine I'd still use One number (C) and let this take over once you start — or show it small beside the big number."
        )) {
            VStack(alignment: .leading, spacing: 6) {
                LabLabel("Prototype · pretend it's…", color: Color(.tertiaryLabel), size: 9)
                Picker("Stage", selection: $stage.animation(.easeInOut(duration: 0.7))) {
                    ForEach(Stage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            chart(tint)
            stats(tint)

            Group {
                switch stage {
                case .inBed: Text("You're usually up by **11:22** — where most of those caps sit.")
                case .up: Text("You usually start **33 min** after waking. Two minutes from now.")
                case .running: Text("12 min in. On plan to finish around **1:04**.")
                case .done: Text("Up **30 min later** than usual and **15 slower** to start; the routine was 3 min quicker.")
                }
            }
            .font(.system(size: 17, weight: .medium)).lineSpacing(3)

            switch stage {
            case .inBed: LabCTA(title: "I'M AWAKE")
            case .up: LabCTA(title: "START ROUTINE")
            case .running: LabCTA(title: "BACK TO ROUTINE")
            case .done:
                HStack {
                    LabLabel("Morning logged")
                    Spacer()
                    LabLabel("Fix a time ›", color: .primary)
                }
            }
        }
    }

    private func chart(_ tint: Color) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                LabClockGrid(range: range, height: height).labels
                ZStack(alignment: .topLeading) {
                    LabClockGrid(range: range, height: height)
                    HStack(spacing: 0) {
                        ForEach(week) { m in
                            LabColumn(goal: Lab.goal, wake: m.wake, start: m.start, end: m.start + m.routine,
                                      range: range, height: height, tint: tint, faded: true)
                        }
                        LabColumn(
                            goal: Lab.goal,
                            wake: stage == .inBed ? nil : t.wake,
                            start: stage == .inBed || stage == .up ? nil : t.start,
                            end: stage == .done ? t.start + t.routine : nil,
                            now: now,
                            range: range, height: height, tint: tint
                        )
                        .frame(width: 64)
                        .background(Color.primary.opacity(0.05))
                        .overlay(alignment: .top) { nowMarker }
                    }
                }
            }
            HStack(spacing: 6) {
                Color.clear.frame(width: 34, height: 12)
                HStack(spacing: 0) {
                    ForEach(week) { m in
                        Text("\(m.day)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                    Text("TODAY").font(.system(size: 9, weight: .bold)).tracking(1).frame(width: 64)
                }
            }
        }
    }

    /// A hairline at the present moment, across today's column.
    @ViewBuilder
    private var nowMarker: some View {
        if let now {
            let y = CGFloat(now - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound) * height
            HStack(spacing: 3) {
                Rectangle().fill(Lab.amber).frame(height: 1.5)
                Text("NOW").font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Lab.amberText)
            }
            .padding(.leading, 4)
            .offset(y: y - 4)
        }
    }

    @ViewBuilder
    private func stats(_ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 0) {
            switch stage {
            case .inBed:
                LabTicker(from: 23 * 60 + 10) { text in
                    LabStat(label: "Past your 11:00 goal", value: "+" + text, color: Lab.amberText, size: 24)
                }
            case .up:
                LabStat(label: "Snooze", value: "52", size: 24).frame(maxWidth: .infinity, alignment: .leading)
                LabTicker(from: 31 * 60 + 7) { text in
                    LabStat(label: "Since you woke", value: text, color: Lab.amberText, size: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(maxWidth: .infinity)
            case .running:
                LabStat(label: "Snooze", value: "52", size: 24).frame(maxWidth: .infinity, alignment: .leading)
                LabStat(label: "To start", value: "48", size: 24).frame(maxWidth: .infinity, alignment: .leading)
                LabTicker(from: 12 * 60 + 4) { text in
                    LabStat(label: "Routine", value: text, color: tint, size: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .done:
                LabStat(label: "Snooze", value: "52", size: 24).frame(maxWidth: .infinity, alignment: .leading)
                LabStat(label: "To start", value: "48", size: 24).frame(maxWidth: .infinity, alignment: .leading)
                LabStat(label: "Routine", value: "24", color: tint, size: 24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Today E · One page, budgets in context

/// Three complaints answered at once:
///
/// 1. *"I want it all to fit on one page with the button staying at the
///    bottom."* Nothing scrolls. The chart gives up height, the header loses
///    a line, and the button is pinned above the tab bar.
/// 2. *"History would flow better as a link near our previous days."* The
///    week chart IS the link — its header carries `ALL MORNINGS ›` — and the
///    tab bar drops to three.
/// 3. *"Both budgets visible, but the one being spent indicates it."* Both
///    bars are always on screen. The one you are spending right now has its
///    today-portion alive — breathing, haloed or ticking a pip — with a NOW
///    tag and a lit label; the other sits quiet at 55% opacity. In bed that
///    is snooze; once up it is activation; during and after the routine
///    neither moves and both simply report the week.
///
/// Three treatments of "alive", switchable in place.
private struct TodayOnePageLab: View {
    enum Stage: String, CaseIterable { case inBed = "In bed", up = "Up", running = "Running", done = "Done" }
    enum BudgetStyle: String, CaseIterable { case meter = "Meter", glow = "Glow", dots = "Dots" }
    enum Baseline: String, CaseIterable { case last = "Last morning", week = "7-day avg", month = "30-day avg" }

    @State private var stage = Stage.inBed
    @State private var style = BudgetStyle.dots
    @State private var baseline = Baseline.week
    @State private var pulse = false

    /// Minutes of each weekly budget already spent before today.
    private let snoozeBefore = 22, activationBefore = 18
    private let budget = 60
    private let t = Lab.today

    /// Today's contribution to each budget. The one being spent right now
    /// ticks; the other is whatever it has already come to.
    private var snoozeToday: Int { stage == .inBed ? 23 : 52 }
    private var activationToday: Int {
        switch stage {
        case .inBed: return 0
        case .up: return 31
        case .running, .done: return t.lag
        }
    }

    /// Which budget is being spent this second. Both stay on screen either
    /// way — only the live one moves.
    private var snoozeIsLive: Bool { stage == .inBed }
    private var activationIsLive: Bool { stage == .up }

    private func budgetColor(_ spent: Int) -> Color {
        if spent > budget { return Color(hex: 0xDB2118) }
        if spent > budget * 3 / 4 { return Lab.amber }
        return .primary
    }

    var body: some View {
        LabFixedScreen(notes: notes) {
            VStack(alignment: .leading, spacing: 0) {
                pickers

                header
                    .padding(.top, 10)

                chartCard
                    .padding(.top, 12)

                Spacer(minLength: 10)

                numberBlock

                budgetBlock
                    .padding(.top, 14)

                Spacer(minLength: 10)
            }
        } bottom: {
            VStack(spacing: 0) {
                LabCTA(title: ctaTitle)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                fakeTabBar
            }
        }
        .onAppear { pulse = true }
    }

    // MARK: Prototype controls

    private var pickers: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Stage", selection: $stage.animation(.easeInOut(duration: 0.45))) {
                ForEach(Stage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Budget style", selection: $style) {
                ForEach(BudgetStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: The page

    /// One line, not three: the date and the goal share a row.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Good morning")
                .font(.system(size: 25, weight: .bold))
            Spacer()
            LabLabel("Goal 6:30", color: Color(.tertiaryLabel), size: 10)
        }
    }

    /// The week, and the way into History.
    private var chartCard: some View {
        let columns = labColumns()
        let goal = Lab.goal
        let live: Int? = {
            switch stage {
            case .inBed: return Lab.goal + snoozeToday
            case .up: return t.wake + activationToday
            case .running: return t.start + 12
            case .done: return nil
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                LabLabel("This week")
                Spacer()
                LabLabel("All mornings ›", color: .primary, size: 10)
            }
            MorningColumnsChart(
                columns: columns,
                scale: ClockScale(columns: columns, goal: goal, now: live, keeping: columns.last),
                tint: labTint,
                height: 124,
                liveIndex: columns.count - 1,
                now: live,
                fadesHistory: true,
                label: { column in
                    Calendar.current.isDateInToday(column.day) ? "TODAY" : Self.dayNumber.string(from: column.day)
                }
            )
        }
        .padding(12)
        .overlay(labBox)
        .contentShape(Rectangle())
    }

    /// The one number for the phase you are in.
    @ViewBuilder
    private var numberBlock: some View {
        if stage == .done {
            // The morning is over: the comparison IS the headline, so the
            // big ticker stands down and gives it the room.
            doneStats
        } else {
            VStack(alignment: .leading, spacing: 4) {
                LabLabel(numberLabel, size: 10)
                LabTicker(from: tickerStart) { text in
                    Text(stage == .inBed ? "+" + text : text)
                        .font(digitFont(50))
                        .monospacedDigit()
                        .contentTransition(.identity)
                        .foregroundStyle(stage == .running ? labTint : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// This morning against a baseline you choose. Each figure carries a
    /// short rule under it — the app's own hard-rule idiom — coloured by
    /// whether the morning beat that baseline, with the baseline's own value
    /// underneath so the colour is never the only thing saying it.
    private var doneStats: some View {
        let base = baselineValues()
        let today = (snooze: t.wake - Lab.goal, activation: t.lag, routine: t.routine)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                LabLabel("This morning vs")
                Spacer()
                Menu {
                    Picker("Baseline", selection: $baseline) {
                        ForEach(Baseline.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(baseline.rawValue)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                compareCell("SNOOZE", today: today.snooze, base: base.snooze, signed: true)
                compareCell("ACTIVATION", today: today.activation, base: base.activation)
                compareCell("ROUTINE", today: today.routine, base: base.routine)
            }
        }
    }

    /// Lower is better for all three of these.
    private func compareCell(_ title: String, today: Int, base: Int, signed: Bool = false) -> some View {
        let delta = today - base
        let better = delta < 0
        let same = abs(delta) <= 1
        let color: Color = same ? .secondary : (better ? labTint : Lab.amber)

        return VStack(alignment: .leading, spacing: 4) {
            LabLabel(title, color: Color(.tertiaryLabel), size: 9)
            Text(Self.minutes(today, signed: signed))
                .font(analogFont(19))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(color)
                .frame(width: 26, height: 2)
            Text(same ? "same as \(Self.minutes(base, signed: signed))"
                 : "\(better ? "−" : "+")\(abs(delta)) vs \(Self.minutes(base, signed: signed))")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func baselineValues() -> (snooze: Int, activation: Int, routine: Int) {
        func mean(_ values: [Int]) -> Int {
            values.isEmpty ? 0 : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        }
        let group: [LabMorning]
        switch baseline {
        case .last:  group = [Lab.mornings[11]]
        case .week:  group = Array(Lab.mornings[5..<12])
        case .month: group = Lab.mornings
        }
        return (mean(group.map { $0.wake - Lab.goal }), mean(group.map(\.lag)), mean(group.map(\.routine)))
    }

    private static func minutes(_ value: Int, signed: Bool = false) -> String {
        let sign = signed && value > 0 ? "+" : (value < 0 ? "−" : "")
        let size = abs(value)
        return size < 60 ? "\(sign)\(size) MIN" : sign + "\(size / 60):" + String(format: "%02d", size % 60)
    }

    // MARK: The budgets, three ways

    /// Both budgets, always. The one being spent has its today-portion
    /// breathing and its label lit; the other sits quiet.
    private var budgetBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            budgetRow("Snooze", before: snoozeBefore, today: snoozeToday, isLive: snoozeIsLive)
            budgetRow("Activation", before: activationBefore, today: activationToday, isLive: activationIsLive)
        }
    }

    private func budgetRow(_ title: String, before: Int, today: Int, isLive: Bool) -> some View {
        let spent = before + today
        let over = spent > budget
        let color = budgetColor(spent)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LabLabel(title, color: isLive ? color : .secondary, size: 9)
                if isLive {
                    // Says which one the movement belongs to, for anyone who
                    // cannot see the pulse.
                    Text("NOW")
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(color, in: Capsule())
                }
                Spacer()
                Text(over ? "\(spent - budget) OVER" : "\(budget - spent) LEFT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(over ? color : .secondary)
                    .contentTransition(.identity)
            }
            switch style {
            case .meter: meter(before: before, today: today, color: color, isLive: isLive)
            case .glow: glow(before: before, today: today, color: color, isLive: isLive)
            case .dots: dots(before: before, today: today, color: color, isLive: isLive)
            }
        }
        .opacity(isLive ? 1 : 0.55)
    }

    /// The week already spent, then today's share on the end of it. Live, that
    /// share breathes.
    private func meter(before: Int, today: Int, color: Color, isLive: Bool) -> some View {
        GeometryReader { geo in
            let unit = geo.size.width / CGFloat(max(budget, before + today))
            HStack(spacing: 0) {
                Rectangle().fill(Color.primary.opacity(0.3))
                    .frame(width: unit * CGFloat(before))
                Rectangle().fill(color)
                    .frame(width: unit * CGFloat(today))
                    .opacity(isLive ? (pulse ? 1 : 0.4) : 1)
                    .animation(isLive ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: pulse)
                Rectangle().fill(Color.primary.opacity(0.07))
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    /// The same bar, but the live one is haloed rather than blinking.
    private func glow(before: Int, today: Int, color: Color, isLive: Bool) -> some View {
        GeometryReader { geo in
            let unit = geo.size.width / CGFloat(max(budget, before + today))
            HStack(spacing: 0) {
                Rectangle().fill(Color.primary.opacity(0.3))
                    .frame(width: unit * CGFloat(before))
                Rectangle().fill(color)
                    .frame(width: unit * CGFloat(today))
                Rectangle().fill(Color.primary.opacity(0.07))
            }
            .shadow(color: isLive ? color.opacity(pulse ? 0.85 : 0.3) : .clear, radius: pulse ? 12 : 5)
            .animation(isLive ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true) : .default, value: pulse)
        }
        .frame(height: 10)
    }

    /// One pip per five minutes, in the app's own dot-matrix register.
    ///
    /// Live, the whole of today's run breathes in unison and stands a little
    /// taller, and the pip currently being filled blinks on the end of it.
    /// Pulsing the edge pip alone (the first version) was far too quiet: one
    /// small square fading among twelve read as a rendering glitch, and on a
    /// budget that moves five minutes at a time it could sit unchanged for
    /// ten minutes at a stretch.
    private func dots(before: Int, today: Int, color: Color, isLive: Bool) -> some View {
        let perPip = 5
        let total = max(budget, before + today) / perPip
        let filledBefore = before / perPip
        let filledNow = (before + today) / perPip

        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                let isToday = index >= filledBefore && index < filledNow
                let isEdge = index == filledNow && isLive
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < filledBefore ? Color.primary.opacity(0.3)
                          : (isToday || isEdge) ? color
                          : Color.primary.opacity(0.07))
                    .frame(height: (isToday || isEdge) && isLive ? 16 : 11)
                    .opacity(isLive ? (isEdge ? (pulse ? 1 : 0.12) : isToday ? (pulse ? 1 : 0.5) : 1) : 1)
                    .animation(
                        isLive && (isToday || isEdge)
                            ? .easeInOut(duration: 1.05).repeatForever(autoreverses: true)
                            : .default,
                        value: pulse
                    )
            }
        }
        .frame(height: 18)
    }

    // MARK: Chrome

    /// Three tabs, not four: History has become a link on the chart.
    private var fakeTabBar: some View {
        HStack(spacing: 0) {
            tab("sun.max", "Today", selected: true)
            tab("timer", "Run", selected: false)
            tab("gearshape", "Settings", selected: false)
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private func tab(_ icon: String, _ title: String, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 17))
            Text(title).font(.system(size: 10))
        }
        .foregroundStyle(selected ? Color.accentColor : .secondary)
        .frame(maxWidth: .infinity)
    }

    // MARK: Text

    private var numberLabel: String {
        switch stage {
        case .inBed: return "PAST YOUR 6:30 GOAL"
        case .up: return "SINCE YOU WOKE AT 11:52"
        case .running: return "INTO THE ROUTINE"
        case .done: return "THIS MORNING"
        }
    }

    private var tickerStart: Int {
        switch stage {
        case .inBed: return 23 * 60 + 10
        case .up: return 31 * 60 + 7
        case .running: return 12 * 60 + 4
        case .done: return 24 * 60
        }
    }

    private var ctaTitle: String {
        switch stage {
        case .inBed: return "I'M AWAKE"
        case .up: return "START ROUTINE"
        case .running: return "BACK TO ROUTINE"
        case .done: return "SEE THE RUN"
        }
    }

    /// The lab's hardcoded mornings as real `MorningColumn`s, so this preview
    /// uses the app's own chart rather than a lookalike.
    private func labColumns() -> [MorningColumn] {
        let today = Calendar.current.startOfDay(for: Date())
        let week = Array(Lab.mornings[5..<12])
        var columns = week.enumerated().map { offset, morning -> MorningColumn in
            let day = Calendar.current.date(byAdding: .day, value: offset - 7, to: today) ?? today
            return MorningColumn(day: day, goal: Lab.goal, wake: morning.wake, start: morning.start, end: morning.start + morning.routine)
        }
        var live = MorningColumn(day: today, goal: Lab.goal)
        switch stage {
        case .inBed: break
        case .up: live.wake = t.wake
        case .running: live.wake = t.wake; live.start = t.start
        case .done: live.wake = t.wake; live.start = t.start; live.end = t.start + t.routine
        }
        columns.append(live)
        return columns
    }

    private static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private var notes: LabNotes {
        LabNotes(
            title: "One page",
            idea: "Everything on one screen with the button pinned: a one-line header, a shorter week chart that doubles as the way into History, the live number, and both weekly budgets underneath — with the one you are spending right now visibly filling. The History tab is gone.",
            pros: [
                "Nothing scrolls, and the button is always under your thumb — this screen is used half-awake.",
                "The budget moves at the moment it can still change your behaviour. Lying in bed watching the snooze bar creep is a reason to get up; the same bar read after breakfast is a receipt.",
                "Both budgets stay readable, so you never lose the week's picture — only the live one moves.",
                "Three tabs instead of four. History stops being a destination and becomes the next tap from the week you are already looking at.",
                "The chart earns its place twice — context now, doorway to more.",
            ],
            cons: [
                "The chart loses ~80pt of height; one week fits here, not two.",
                "A pulsing indicator breaks the app's everything-snaps rule. It is the only moving thing on the screen, which is either the point or a wart — and two bars where one moves is a subtler signal than it sounds on paper.",
                "Motion alone cannot carry it (colour-blindness, a glance from across the room, Reduce Motion), hence the NOW tag and the lit label. If those are doing the work, the pulse may be decoration.",
                "Tight at the bottom: two budget rows plus a button plus a tab bar leaves the number less room than it had.",
                "The comparison only exists once the morning is done, so the baseline picker is invisible for most of the day — it may want a home in the week chart's header instead.",
                "Dots quantise to 5 min: early in the week the live run can sit unchanged for ten minutes, which undercuts the point of showing it live.",
            ],
            take: "Meter is my pick: today's share is a distinct block you can actually measure against the rest of the week, and the pulse is unmistakable without being loud. Dots are the most on-brand — the whole app is dot-matrix — but they quantise to 5 min, so early on nothing moves for ages and the signal dies. Glow is the prettiest and the least legible: a halo on a 10pt bar reads as a rendering artefact more than a state, and it is the one most likely to look broken with Reduce Motion on."
        )
    }
}

/// A mockup that fills the screen: no scrolling, a pinned bottom slot, and
/// the real tab bar hidden so the page can own the whole height.
private struct LabFixedScreen<Content: View, Bottom: View>: View {
    let notes: LabNotes
    @ViewBuilder let content: Content
    @ViewBuilder let bottom: Bottom
    @State private var showingNotes = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 22)
            bottom
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .navigationTitle(notes.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNotes = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Pros and cons")
            }
        }
        .sheet(isPresented: $showingNotes) { LabNotesSheet(notes: notes) }
    }
}

#endif
