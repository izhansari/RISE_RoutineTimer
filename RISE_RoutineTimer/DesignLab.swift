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
                Text("One morning, read at a glance. Use the picker at the top of each to step through the morning's states. E became the real screen.")
            }

            Section {
                NavigationLink("F · Pruned: the chart and one sentence") { TodayPrunedLab() }
                NavigationLink("G · Receipt: the morning printed line by line") { TodayReceiptLinesLab() }
                NavigationLink("H · Habit: a month of dots") { TodayHabitLab() }
                NavigationLink("I · Today against usual") { TodayVersusUsualLab() }
            } header: {
                Text("Today, second round")
            } footer: {
                Text("Answers to \"it's information overload\": each keeps one idea from the current page and drops the rest. No budgets, no stopwatch. Step through In bed → Up → Running → Done on each.")
            }

            Section {
                NavigationLink("J · Today vs usual, in History's words") { TodayUsualReadoutLab() }
                NavigationLink("K · The week, History's chart") { TodayWeekReadoutLab() }
                NavigationLink("L · Health bars first") { TodayHealthFirstLab() }
            } header: {
                Text("Today, third round")
            } footer: {
                Text("I's comparison, told with History's readout box and mark labels, and the two budgets as health bars that drain from full. The pale end of each bar is what today has taken.")
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

// MARK: - Today, second round · shared

/// The four moments of a morning the second-round mockups step through.
private enum LabMoment: String, CaseIterable { case inBed = "In bed", up = "Up", running = "Running", done = "Done" }

/// The facts every second-round mockup is drawn from — the owner's Sat Sep 19
/// (woke 11:52 against an assumed 11:00 goal, started 12:40, 24 minutes of
/// routine) and the seven mornings before it. A poor morning on purpose: the
/// test of a landing page is whether it can say "late" without shouting.
private enum LabToday {
    static let goal = Lab.goal                 // 11:00
    static let wake = 712                      // 11:52
    static let start = 760                     // 12:40
    static let end = 784                       // 1:04
    static let routine = 24
    /// Seven-morning usual.
    static let usualWake = 682                 // 11:22
    static let usualLag = Lab.usualLag         // 33
    static let usualRoutine = Lab.usualRoutine // 27
    static let streak = 4

    /// Where the clock is in each moment.
    static func now(_ moment: LabMoment) -> Int {
        switch moment {
        case .inBed: return 672        // 11:12
        case .up: return 730           // 12:10
        case .running: return 770      // 12:50
        case .done: return end
        }
    }

    /// The one sentence the page says, in each moment. Plain words, the
    /// comparison to usual built in, and always ending on what to do.
    static func sentence(_ moment: LabMoment) -> String {
        switch moment {
        case .inBed:
            return "12 min past your 11:00 goal. You're usually up by 11:22 — get up now and you beat it."
        case .up:
            return "Up at 11:52. You usually start within 33 min; it's been 18."
        case .running:
            return "10 min into the routine. Done by 1:04 on plan."
        case .done:
            return "Done at 1:04. The routine took 24 min, 3 quicker than usual. You woke 52 min late."
        }
    }

    static func cta(_ moment: LabMoment) -> String {
        switch moment {
        case .inBed: return "I'M AWAKE"
        case .up: return "START ROUTINE"
        case .running: return "BACK TO ROUTINE"
        case .done: return "MORNING LOGGED"
        }
    }

    /// The last seven mornings including today, as columns.
    static let week: [LabMorning] = Array(Lab.mornings.suffix(7))
}

private struct LabMomentPicker: View {
    @Binding var moment: LabMoment
    var body: some View {
        Picker("Moment", selection: $moment.animation(.easeInOut(duration: 0.3))) {
            ForEach(LabMoment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// The small header every second-round page shares: the date and the goal
/// on one quiet line, the gear where it is today. No greeting — it was the
/// largest type on the page and carried nothing.
private struct LabDateLine: View {
    var body: some View {
        HStack {
            LabLabel("Sat 19 Sep", color: .primary)
            Spacer()
            LabLabel("Goal 11:00")
            Image(systemName: "gearshape")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
        }
    }
}

/// The one sentence, set in the system face at reading size — the receipt
/// face is for labels and digits, and a sentence is neither.
private struct LabSentence: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .regular))
            .lineSpacing(3)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.identity)
    }
}

/// Today's column in a given moment, so the mockups agree about what is
/// drawn when.
private extension LabColumn {
    static func today(_ moment: LabMoment, range: ClosedRange<Int>, height: CGFloat, tint: Color) -> LabColumn {
        switch moment {
        case .inBed:
            return LabColumn(goal: LabToday.goal, wake: nil, start: nil, end: nil, now: LabToday.now(.inBed), range: range, height: height, tint: tint)
        case .up:
            return LabColumn(goal: LabToday.goal, wake: LabToday.wake, start: nil, end: nil, now: LabToday.now(.up), range: range, height: height, tint: tint)
        case .running:
            return LabColumn(goal: LabToday.goal, wake: LabToday.wake, start: LabToday.start, end: nil, now: LabToday.now(.running), range: range, height: height, tint: tint)
        case .done:
            return LabColumn(goal: LabToday.goal, wake: LabToday.wake, start: LabToday.start, end: LabToday.end, range: range, height: height, tint: tint)
        }
    }
}

// MARK: - Today F · Pruned

/// The current page with everything but its best element cut. The week
/// chart stays, because it is the one thing on the page that carries the
/// shape of the week; the stopwatch, the budgets and the greeting go, and
/// the number-plus-note becomes one sentence that already has the comparison
/// in it. The lowest-risk option: nothing new to learn.
private struct TodayPrunedLab: View {
    @State private var moment = LabMoment.inBed

    private let range = 600...840   // 10AM – 2PM
    private let chartHeight: CGFloat = 230

    var body: some View {
        LabFixedScreen(notes: notes) {
            VStack(alignment: .leading, spacing: 0) {
                LabMomentPicker(moment: $moment)
                LabDateLine().padding(.top, 14)
                chart.padding(.top, 16)
                Spacer(minLength: 12)
                LabSentence(text: LabToday.sentence(moment))
                Spacer(minLength: 18)
            }
        } bottom: {
            LabCTA(title: LabToday.cta(moment)).padding(.horizontal, 22).padding(.bottom, 10)
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LabLabel("This week")
                Spacer()
                LabLabel("All mornings ›", color: .primary)
            }
            HStack(alignment: .top, spacing: 6) {
                LabClockGrid(range: range, height: chartHeight).labels
                ZStack(alignment: .top) {
                    LabClockGrid(range: range, height: chartHeight)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(LabToday.week.enumerated()), id: \.offset) { index, morning in
                            let isToday = index == LabToday.week.count - 1
                            if isToday {
                                LabColumn.today(moment, range: range, height: chartHeight, tint: labTint)
                            } else {
                                LabColumn(goal: LabToday.goal, wake: morning.wake, start: morning.start, end: morning.start + morning.routine, range: range, height: chartHeight, tint: labTint, faded: true)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 40, height: 1)
                ForEach(Array(LabToday.week.enumerated()), id: \.offset) { index, morning in
                    Text(index == LabToday.week.count - 1 ? "TODAY" : "\(morning.day)")
                        .font(.system(size: 9, weight: index == LabToday.week.count - 1 ? .bold : .medium))
                        .foregroundStyle(index == LabToday.week.count - 1 ? .primary : .tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .overlay(labBox)
    }

    private var notes: LabNotes {
        LabNotes(
            title: "F · Pruned",
            idea: "Keep the week chart, cut everything else: no greeting, no stopwatch, no budgets. One sentence replaces the number and its note, with the comparison to usual written into it.",
            pros: [
                "Nothing new to learn — the mark is the same one History uses.",
                "The sentence does what the 50pt number pretended to: tells you where you stand and what to do.",
                "Half the screen is white. It reads at a glance.",
            ],
            cons: [
                "The chart still needs decoding (clock, five marks) and still leads the page.",
                "A bad week is still a wall of long dotted lines before you have done anything.",
                "The budgets are gone with nowhere to go yet — they would need a home on History.",
            ],
            take: "The safe cut. If the chart is the thing you actually look at in the morning, this is the answer; if you don't, it is still the wrong headline."
        )
    }
}

// MARK: - Today G · Receipt lines

/// The morning printed as a receipt, one line per moment: WOKE, STARTED,
/// ROUTINE. Lines not yet reached are blank; the current one ticks; each
/// finished line carries its verdict against usual in small type under the
/// value. The week is a row of seven marks, not a chart. The brand's own
/// idiom — the Fake Receipt face, hard rules — doing the page's work.
private struct TodayReceiptLinesLab: View {
    @State private var moment = LabMoment.inBed

    var body: some View {
        LabFixedScreen(notes: notes) {
            VStack(alignment: .leading, spacing: 0) {
                LabMomentPicker(moment: $moment)
                LabDateLine().padding(.top, 14)
                receipt.padding(.top, 22)
                Spacer(minLength: 12)
                weekRow
                Spacer(minLength: 12)
                LabSentence(text: LabToday.sentence(moment))
                Spacer(minLength: 18)
            }
        } bottom: {
            LabCTA(title: LabToday.cta(moment)).padding(.horizontal, 22).padding(.bottom, 10)
        }
    }

    private var receipt: some View {
        VStack(spacing: 0) {
            line("Woke",
                 value: moment == .inBed ? nil : Lab.clock(LabToday.wake),
                 live: moment == .inBed ? LabToday.now(.inBed) - LabToday.goal : nil,
                 liveLabel: "past goal",
                 verdict: moment == .inBed ? nil : "52 MIN LATE · USUALLY 22",
                 color: Lab.amberText)
            ReceiptRule()
            line("Started",
                 value: [.running, .done].contains(moment) ? Lab.clock(LabToday.start) : nil,
                 live: moment == .up ? LabToday.now(.up) - LabToday.wake : nil,
                 liveLabel: "since waking",
                 verdict: [.running, .done].contains(moment) ? "48 MIN AFTER WAKING · USUALLY 33" : nil,
                 color: Lab.amberText)
            ReceiptRule()
            line("Routine",
                 value: moment == .done ? "24:00" : nil,
                 live: moment == .running ? LabToday.now(.running) - LabToday.start : nil,
                 liveLabel: "done by 1:04",
                 verdict: moment == .done ? "3 MIN QUICKER THAN USUAL" : nil,
                 color: labTint)
        }
    }

    /// One receipt line. A blank value is printed as a dash in the tertiary
    /// ink — the line is coming, not missing.
    private func line(_ label: String, value: String?, live: Int?, liveLabel: String, verdict: String?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(analogFont(17))
                .foregroundStyle(value == nil && live == nil ? Color(.tertiaryLabel) : .primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let value {
                    Text(value).font(analogFont(30)).monospacedDigit()
                } else if let live {
                    LabTicker(from: live * 60) { text in
                        Text(text).font(analogFont(30)).monospacedDigit().foregroundStyle(color)
                    }
                } else {
                    Text("—").font(analogFont(30)).foregroundStyle(Color(.tertiaryLabel))
                }
                if let verdict {
                    LabLabel(verdict, color: color, size: 9)
                } else if live != nil {
                    LabLabel(liveLabel, color: .secondary, size: 9)
                }
            }
        }
        .padding(.vertical, 12)
        .contentTransition(.identity)
    }

    /// Seven marks for seven days: filled when you were up by the goal,
    /// hollow when late, dashed when nothing was logged, today ringed.
    private var weekRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LabLabel("This week")
                Spacer()
                LabLabel("\(LabToday.streak) day streak", color: .primary)
            }
            HStack(spacing: 0) {
                ForEach(Array(LabToday.week.enumerated()), id: \.offset) { index, morning in
                    let isToday = index == LabToday.week.count - 1
                    let onTime = morning.wake <= LabToday.goal
                    VStack(spacing: 6) {
                        ZStack {
                            if isToday && moment == .inBed {
                                Circle().strokeBorder(Color.primary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(width: 18, height: 18)
                            } else if onTime {
                                Circle().fill(labTint).frame(width: 18, height: 18)
                            } else {
                                Circle().strokeBorder(Lab.amber, lineWidth: 2).frame(width: 18, height: 18)
                            }
                            if isToday {
                                Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1).frame(width: 26, height: 26)
                            }
                        }
                        Text(String(morning.weekday.prefix(1)))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isToday ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .overlay(labBox)
    }

    private var notes: LabNotes {
        LabNotes(
            title: "G · Receipt",
            idea: "Print the morning as three receipt lines — WOKE, STARTED, ROUTINE — filling in as they happen. The line you are on ticks; a finished line carries its verdict against usual in small type. The week is seven marks, not a chart.",
            pros: [
                "It is the brand: the receipt face and the hard rules doing the page's own work.",
                "Reads top to bottom as a checklist. You can see what is left.",
                "Every number comes with its comparison, so 11:52 is never a bare fact.",
                "Fits on one screen with room to spare, in every state.",
            ],
            cons: [
                "No shape of the week — you get on-time / late per day, not how late.",
                "Three verdicts in amber on a bad morning is still three tellings-off.",
                "The routine line duplicates what the Run tab and the summary already show.",
            ],
            take: "My favourite for a landing page: it answers 'where am I in the morning' before anything else, and the week is a glance, not a study."
        )
    }
}

// MARK: - Today H · Habit

/// The landing page is about the habit, not the metrics: four weeks of
/// mornings as dots, today's the big one, alive. On time is the theme colour,
/// late is amber, missed is a hollow grey. The streak is the headline. One
/// sentence about now, and the button. Everything measured lives in History.
private struct TodayHabitLab: View {
    @State private var moment = LabMoment.inBed
    @State private var pulse = false

    private enum Day { case onTime, late, missed, blank }

    /// Four weeks, Monday first, ending on today (Sat). The first two weeks
    /// predate the data and are drawn blank.
    private var grid: [[Day]] {
        var days: [Day] = Array(repeating: .blank, count: 14)
        // Sep 7 (Mon) … Sep 19 (Sat), then Sun blank to finish the row.
        for morning in Lab.mornings.dropLast() {
            days.append(morning.wake <= LabToday.goal ? .onTime : .late)
        }
        days.append(.blank) // today, drawn separately
        days.append(.blank) // Sunday still to come
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    var body: some View {
        LabFixedScreen(notes: notes) {
            VStack(alignment: .leading, spacing: 0) {
                LabMomentPicker(moment: $moment)
                LabDateLine().padding(.top, 14)
                headline.padding(.top, 22)
                dots.padding(.top, 20)
                Spacer(minLength: 12)
                LabSentence(text: LabToday.sentence(moment))
                Spacer(minLength: 18)
            }
        } bottom: {
            LabCTA(title: LabToday.cta(moment)).padding(.horizontal, 22).padding(.bottom, 10)
        }
        .onAppear { pulse = true }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(LabToday.streak)")
                .font(digitFont(56))
            VStack(alignment: .leading, spacing: 2) {
                LabLabel("mornings in a row", color: .primary)
                LabLabel("best 6 · all mornings ›")
            }
        }
    }

    private var dots: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { d in
                    Text(d).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(grid.enumerated()), id: \.offset) { row, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { col, day in
                        let isToday = row == grid.count - 1 && col == 5
                        ZStack {
                            if isToday {
                                todayDot
                            } else {
                                dot(day)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                    }
                }
            }
        }
        .padding(12)
        .overlay(labBox)
    }

    private func dot(_ day: Day) -> some View {
        Group {
            switch day {
            case .onTime: Circle().fill(labTint)
            case .late: Circle().fill(Lab.amber.opacity(0.85))
            case .missed: Circle().strokeBorder(Color(.tertiaryLabel), lineWidth: 1.5)
            case .blank: Circle().fill(Color.primary.opacity(0.06))
            }
        }
        .frame(width: 16, height: 16)
    }

    /// Today: hollow and breathing in bed, filled amber once up late, the
    /// theme colour once the routine is done.
    private var todayDot: some View {
        ZStack {
            switch moment {
            case .inBed:
                Circle().strokeBorder(Color.primary, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .opacity(pulse ? 0.35 : 1)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            case .up, .running:
                Circle().fill(Lab.amber.opacity(0.85)).frame(width: 24, height: 24)
                Circle().strokeBorder(Color.primary, lineWidth: 1.5).frame(width: 30, height: 30)
            case .done:
                Circle().fill(Lab.amber.opacity(0.85)).frame(width: 24, height: 24)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
        }
    }

    private var notes: LabNotes {
        LabNotes(
            title: "H · Habit",
            idea: "Lead with the streak and a month of dots — on time, late, missed — with today's dot alive. The numbers move to History. One sentence says where you are; the button says what to do.",
            pros: [
                "Consistency is the thing the app is for, and this shows it directly: a month at a glance.",
                "Cheap to read half-awake: colour and a count, no clock, no axis.",
                "A late morning is one amber dot among many, not a wall of red.",
            ],
            cons: [
                "Loses all magnitude: 5 minutes late and 90 minutes late are the same dot.",
                "Two states of 'late' (late but ran the routine, late and skipped it) need a mark each or the grid lies.",
                "The activation and routine-length stories vanish from the landing page entirely.",
            ],
            take: "Strongest as a feeling, weakest as information. Right if the landing page's only job is 'keep going'; pair it with a proper History."
        )
    }
}

// MARK: - Today I · Today against usual

/// Only today's mark, drawn large, with a faded 'usual' column beside it —
/// the seven-morning average wake, start and end. The comparison is spatial:
/// today's cap below usual's is a late morning, a shorter box is a quicker
/// routine. Clock at the left, each of today's marks labelled in place. The
/// week and the budgets are History's.
private struct TodayVersusUsualLab: View {
    @State private var moment = LabMoment.inBed

    private let range = 630...810   // 10:30 – 1:30
    private let height: CGFloat = 290

    private func y(_ minutes: Int) -> CGFloat {
        CGFloat(minutes - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound) * height
    }

    var body: some View {
        LabFixedScreen(notes: notes) {
            VStack(alignment: .leading, spacing: 0) {
                LabMomentPicker(moment: $moment)
                LabDateLine().padding(.top, 14)
                figure.padding(.top, 16)
                Spacer(minLength: 12)
                LabSentence(text: LabToday.sentence(moment))
                Spacer(minLength: 18)
            }
        } bottom: {
            LabCTA(title: LabToday.cta(moment)).padding(.horizontal, 22).padding(.bottom, 10)
        }
    }

    private var figure: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LabLabel("Today")
                Spacer()
                LabLabel("Usual = last 7 · all mornings ›")
            }
            HStack(alignment: .top, spacing: 6) {
                LabClockGrid(range: range, height: height).labels
                ZStack(alignment: .topLeading) {
                    LabClockGrid(range: range, height: height)
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: 0)
                        // Usual, faded, with its own small labels.
                        LabColumn(goal: LabToday.goal, wake: LabToday.usualWake, start: LabToday.usualWake + LabToday.usualLag, end: LabToday.usualWake + LabToday.usualLag + LabToday.usualRoutine, range: range, height: height, tint: labTint, faded: true)
                            .frame(width: 70)
                        Spacer(minLength: 0)
                        LabColumn.today(moment, range: range, height: height, tint: labTint)
                            .frame(width: 70)
                        Spacer(minLength: 0)
                    }
                    annotations
                }
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 40, height: 1)
                Spacer(minLength: 0)
                LabLabel("Usual", color: Color(.tertiaryLabel), size: 9).frame(width: 70)
                Spacer(minLength: 0)
                LabLabel("Today", color: .primary, size: 9).frame(width: 70)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .overlay(labBox)
    }

    /// Today's numbers floated beside today's marks. Their x is the right
    /// edge of the plot; the geometry here is by eye, which is what a
    /// mockup is for.
    private var annotations: some View {
        // A GeometryReader is greedy; pinned to the plot's height so it
        // cannot stretch the card to the bottom of the screen.
        GeometryReader { geo in
            let x = geo.size.width * 0.5 + 35 + 44
            Group {
                switch moment {
                case .inBed:
                    chip("+12 MIN", color: Lab.amberText, x: x, y: y(LabToday.now(.inBed)))
                case .up:
                    chip("11:52 · +52", color: Lab.amberText, x: x, y: y(LabToday.wake))
                case .running:
                    chip("11:52 · +52", color: Lab.amberText, x: x, y: y(LabToday.wake))
                    chip("48M", color: Lab.lagGrey, x: x, y: (y(LabToday.wake) + y(LabToday.start)) / 2)
                case .done:
                    chip("11:52 · +52", color: Lab.amberText, x: x, y: y(LabToday.wake))
                    chip("48M", color: Lab.lagGrey, x: x, y: (y(LabToday.wake) + y(LabToday.start)) / 2)
                    chip("24M", color: labTint, x: x, y: (y(LabToday.start) + y(LabToday.end)) / 2)
                }
            }
        }
        .frame(height: height)
    }

    private func chip(_ text: String, color: Color, x: CGFloat, y: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(1)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color(.systemBackground).opacity(0.9), in: Capsule())
            .fixedSize()
            .position(x: x, y: y)
    }

    private var notes: LabNotes {
        LabNotes(
            title: "I · Today vs usual",
            idea: "One column for today, one faded column for your usual morning, on the same clock. Late is 'lower than usual', quick is 'shorter box' — a comparison you see rather than compute. The week itself is one tap away.",
            pros: [
                "The mark is the same one History uses, so nothing new to learn — and at this size it finally reads without squinting.",
                "The comparison is built into the picture; no baseline table, no verdict text needed.",
                "A bad morning is one column a little lower than another, not a red screen.",
            ],
            cons: [
                "Still a clock chart at 6:30am — the axis has to be read.",
                "No trend: you cannot tell if the week has been getting better.",
                "'Usual' hides a lot: a wild week averages to a calm column.",
            ],
            take: "The honest middle: keeps the app's one drawing, drops everything that repeated it. Pairs naturally with G's sentence and History's week."
        )
    }
}

// MARK: - Today, third round · shared

/// Mock budget spend, chosen so the bars show all three states across the
/// morning: healthy, low, and empty.
private enum LabBudget {
    static let total = 60
    static let snoozeBefore = 10
    static let activationBefore = 8
    static func snoozeToday(_ m: LabMoment) -> Int { m == .inBed ? 12 : 52 }
    static func activationToday(_ m: LabMoment) -> Int {
        switch m {
        case .inBed: return 0
        case .up: return 18
        case .running, .done: return 48
        }
    }
    static let red = Color(hex: 0xDB2118)
}

/// A weekly allowance as a health bar. Full at the start of the week, it
/// drains as minutes are spent. The solid part is what is left; the pale
/// part beside it is what today has taken (the "damage" a game shows before
/// it fades); the track is what earlier days took. The theme colour while
/// healthy, amber under a quarter, red and empty once it is gone.
private struct LabHealthBar: View {
    let title: String
    let before: Int
    let today: Int
    var budget = LabBudget.total
    var live = false
    var large = false
    @State private var pulse = false

    private var remaining: Int { budget - before - today }
    private var startFraction: Double { max(0, Double(budget - before)) / Double(budget) }
    private var nowFraction: Double { max(0, Double(remaining)) / Double(budget) }
    private var color: Color {
        if remaining <= 0 { return LabBudget.red }
        if nowFraction < 0.25 { return Lab.amber }
        return labTint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 8 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                LabLabel(title, color: live ? .primary : .secondary, size: large ? 11 : 9)
                if live {
                    Text("NOW")
                        .font(.system(size: 7.5, weight: .bold)).tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(color, in: Capsule())
                }
                Spacer()
                if large {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(remaining > 0 ? "\(remaining)" : "0").font(analogFont(24)).monospacedDigit()
                            .foregroundStyle(remaining <= 0 ? LabBudget.red : .primary)
                        LabLabel(remaining > 0 ? "min left" : "empty · \(-remaining) over", color: remaining <= 0 ? LabBudget.red : .secondary, size: 9)
                    }
                } else {
                    LabLabel(remaining > 0 ? "\(remaining) min left" : remaining == 0 ? "empty" : "empty · \(-remaining) over",
                             color: remaining <= 0 ? LabBudget.red : .primary, size: 9)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.07))
                    Rectangle().fill(color.opacity(0.25)).frame(width: geo.size.width * startFraction)
                    Rectangle().fill(color).frame(width: geo.size.width * nowFraction)
                        .opacity(live && pulse ? 0.55 : 1)
                        .animation(live ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: pulse)
                    // Ten-minute notches, in the app's dot-matrix register.
                    HStack(spacing: 0) {
                        ForEach(0..<(budget / 10), id: \.self) { i in
                            Color.clear.overlay(alignment: .trailing) {
                                if i < budget / 10 - 1 { Rectangle().fill(Color(.systemBackground)).frame(width: 2) }
                            }
                        }
                    }
                }
            }
            .frame(height: large ? 18 : 10)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .onAppear { pulse = true }
    }
}

/// History's readout stat: tracked grey label, receipt-face value, and here
/// an optional small note under it for the comparison.
private struct LabReadoutStat: View {
    let label: String
    let value: String
    var color: Color = .primary
    var note: String? = nil
    var noteColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(1.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(analogFont(21)).monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(note ?? " ")
                .font(.system(size: 8.5, weight: .semibold)).tracking(1.1)
                .foregroundStyle(noteColor)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentTransition(.identity)
    }
}

/// History's mark label: a small bordered chip beside the mark it names.
private func labMarkChip(_ text: String, color: Color) -> some View {
    Text(text)
        .font(.system(size: 9, weight: .bold)).tracking(0.8)
        .foregroundStyle(color)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Color(.systemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .fixedSize()
}

/// Today's three figures in each moment, with the comparison to usual.
private enum LabFigures {
    struct Figure { let value: String; let note: String?; let color: Color; let noteColor: Color }

    static func woke(_ m: LabMoment) -> Figure {
        m == .inBed
            ? Figure(value: "+12 MIN", note: "USUALLY UP 11:22", color: Lab.amberText, noteColor: .secondary)
            : Figure(value: "11:52", note: "30 LATER THAN USUAL", color: .primary, noteColor: Lab.amberText)
    }
    static func toStart(_ m: LabMoment) -> Figure {
        switch m {
        case .inBed: return Figure(value: "—", note: "USUALLY 33 MIN", color: Color(.tertiaryLabel), noteColor: .secondary)
        case .up: return Figure(value: "18 MIN", note: "SO FAR · USUALLY 33", color: .primary, noteColor: .secondary)
        case .running, .done: return Figure(value: "48 MIN", note: "15 LONGER THAN USUAL", color: .primary, noteColor: Lab.amberText)
        }
    }
    static func routine(_ m: LabMoment) -> Figure {
        switch m {
        case .inBed, .up: return Figure(value: "—", note: "USUALLY 27 MIN", color: Color(.tertiaryLabel), noteColor: .secondary)
        case .running: return Figure(value: "10 MIN", note: "DONE BY 1:04", color: labTint, noteColor: .secondary)
        case .done: return Figure(value: "24 MIN", note: "3 QUICKER THAN USUAL", color: labTint, noteColor: labTint)
        }
    }
}

/// The readout box as History draws it: a title row, then the three stats.
private struct LabTodayReadout<Trailing: View>: View {
    let moment: LabMoment
    var title = "TODAY"
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).tracking(1.6)
                Spacer()
                trailing
            }
            .frame(height: 24)
            HStack(alignment: .top, spacing: 12) {
                stat("Woke", LabFigures.woke(moment))
                stat("To start", LabFigures.toStart(moment))
                stat("Routine", LabFigures.routine(moment))
            }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }

    private func stat(_ label: String, _ f: LabFigures.Figure) -> some View {
        LabReadoutStat(label: label, value: f.value, color: f.color, note: f.note, noteColor: f.noteColor)
    }
}

/// Today's labelled marks, History style, for a column of the given width.
private func labTodayChips(_ m: LabMoment, y: (Int) -> CGFloat, side: CGFloat) -> some View {
    ZStack(alignment: .top) {
        switch m {
        case .inBed:
            labMarkChip("+12M", color: Lab.amberText).offset(x: side, y: y(LabToday.now(.inBed)) - 8)
        case .up:
            labMarkChip("11:52", color: .primary).offset(x: side, y: y(LabToday.wake) - 8)
            labMarkChip("18M", color: Lab.lagGrey).offset(x: side, y: (y(LabToday.wake) + y(LabToday.now(.up))) / 2 - 8)
        case .running:
            labMarkChip("11:52", color: .primary).offset(x: side, y: y(LabToday.wake) - 8)
            labMarkChip("48M", color: Lab.lagGrey).offset(x: side, y: (y(LabToday.wake) + y(LabToday.start)) / 2 - 8)
            labMarkChip("10M", color: labTint).offset(x: side, y: (y(LabToday.start) + y(LabToday.now(.running))) / 2 - 8)
        case .done:
            labMarkChip("11:52", color: .primary).offset(x: side, y: y(LabToday.wake) - 8)
            labMarkChip("48M", color: Lab.lagGrey).offset(x: side, y: (y(LabToday.wake) + y(LabToday.start)) / 2 - 8)
            labMarkChip("24M", color: labTint).offset(x: side, y: (y(LabToday.start) + y(LabToday.end)) / 2 - 8)
        }
    }
}

private func labBudgets(_ m: LabMoment, large: Bool = false) -> some View {
    VStack(spacing: large ? 18 : 12) {
        LabHealthBar(title: "Snooze", before: LabBudget.snoozeBefore, today: LabBudget.snoozeToday(m), live: m == .inBed, large: large)
        LabHealthBar(title: "Activation", before: LabBudget.activationBefore, today: LabBudget.activationToday(m), live: m == .up, large: large)
    }
}

// MARK: - Today J · Today vs usual, in History's words

/// I, retold: the readout box leads (today's three figures, each with its
/// difference from usual under it), then today's column beside a faded usual
/// column with History's chips on both, then the two health bars.
private struct TodayUsualReadoutLab: View {
    @State private var moment = LabMoment.inBed
    private let range = 630...810
    private let height: CGFloat = 220

    private func y(_ minutes: Int) -> CGFloat {
        CGFloat(minutes - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound) * height
    }

    var body: some View {
        LabFixedScreen(notes: notes) {
            VStack(alignment: .leading, spacing: 0) {
                LabMomentPicker(moment: $moment)
                LabDateLine().padding(.top, 14)
                LabTodayReadout(moment: moment) {
                    LabLabel("vs last 7", color: .secondary, size: 9)
                }
                .padding(.top, 14)
                chart.padding(.top, 12)
                Spacer(minLength: 10)
                labBudgets(moment)
                Spacer(minLength: 14)
            }
        } bottom: {
            LabCTA(title: LabToday.cta(moment)).padding(.horizontal, 22).padding(.bottom, 10)
        }
    }

    private var chart: some View {
        HStack(alignment: .top, spacing: 6) {
            LabClockGrid(range: range, height: height).labels
            ZStack(alignment: .top) {
                LabClockGrid(range: range, height: height)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LabColumn(goal: LabToday.goal, wake: LabToday.usualWake, start: LabToday.usualWake + LabToday.usualLag,
                              end: LabToday.usualWake + LabToday.usualLag + LabToday.usualRoutine, range: range, height: height, tint: labTint, faded: true)
                        .frame(width: 60)
                        .overlay(alignment: .top) {
                            ZStack(alignment: .top) {
                                labMarkChip("11:22", color: Color(.tertiaryLabel)).offset(x: -52, y: y(LabToday.usualWake) - 8)
                                labMarkChip("33M", color: Color(.tertiaryLabel)).offset(x: -52, y: y(LabToday.usualWake + 16) - 8)
                                labMarkChip("27M", color: Color(.tertiaryLabel)).offset(x: -52, y: y(LabToday.usualWake + 46) - 8)
                            }
                        }
                    Spacer(minLength: 0)
                    LabColumn.today(moment, range: range, height: height, tint: labTint)
                        .frame(width: 60)
                        .overlay(alignment: .top) { labTodayChips(moment, y: y, side: 54) }
                    Spacer(minLength: 0)
                }
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        LabLabel("Usual", color: Color(.tertiaryLabel), size: 8).frame(width: 60)
                        Spacer(minLength: 0)
                        LabLabel("Today", color: .primary, size: 8).frame(width: 60)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: height)
        }
        .padding(.vertical, 4)
    }

    private var notes: LabNotes {
        LabNotes(
            title: "J · Usual, History's words",
            idea: "Today vs usual, but spoken the way History speaks: the same boxed readout (WOKE · TO START · ROUTINE) with each figure's difference from usual underneath, and History's little labels on the marks. The budgets become health bars that drain from full.",
            pros: [
                "One vocabulary across the app — learn the readout on History, read it here.",
                "Every number arrives with its comparison, so nothing needs working out.",
                "Health bars say 'you have 38 minutes of slack left this week', which is a reason to get up, not a bill.",
            ],
            cons: [
                "Three layers — readout, chart, bars — is still a lot for 6:30am.",
                "The chart now mostly repeats the readout in pictures.",
            ],
            take: "The most complete of the three. If it still feels busy, the chart is the thing to cut — which is L."
        )
    }
}

// MARK: - Today K · The week, History's chart

/// The History chart itself at seven days, today growing on the end with its
/// marks labelled, under History's readout — today's figures, compared with
/// the 7- or 30-day average by the same pills History uses. Health bars below.
private struct TodayWeekReadoutLab: View {
    @State private var moment = LabMoment.inBed
    @State private var period = "7 DAYS"
    private let range = 600...840
    private let height: CGFloat = 190

    private func y(_ minutes: Int) -> CGFloat {
        CGFloat(minutes - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound) * height
    }

    var body: some View {
        LabFixedScreen(notes: notes) {
            VStack(alignment: .leading, spacing: 0) {
                LabMomentPicker(moment: $moment)
                LabDateLine().padding(.top, 14)
                LabTodayReadout(moment: moment, title: "TODAY VS") { pills }
                    .padding(.top, 14)
                chart.padding(.top, 12)
                Spacer(minLength: 10)
                labBudgets(moment)
                Spacer(minLength: 14)
            }
        } bottom: {
            LabCTA(title: LabToday.cta(moment)).padding(.horizontal, 22).padding(.bottom, 10)
        }
    }

    private var pills: some View {
        HStack(spacing: 4) {
            ForEach(["7 DAYS", "30 DAYS"], id: \.self) { option in
                let isOn = option == period
                Button { period = option } label: {
                    Text(option)
                        .font(.system(size: 9, weight: .semibold)).tracking(1.1)
                        .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary.opacity(0.55))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background {
                            if isOn { Capsule().fill(Color.primary) }
                            else { Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chart: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                LabClockGrid(range: range, height: height).labels
                ZStack(alignment: .top) {
                    LabClockGrid(range: range, height: height)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(LabToday.week.enumerated()), id: \.offset) { index, morning in
                            if index == LabToday.week.count - 1 {
                                LabColumn.today(moment, range: range, height: height, tint: labTint)
                                    .overlay(alignment: .top) { labTodayChips(moment, y: y, side: -34) }
                            } else {
                                LabColumn(goal: LabToday.goal, wake: morning.wake, start: morning.start, end: morning.start + morning.routine,
                                          range: range, height: height, tint: labTint, faded: true)
                            }
                        }
                    }
                }
                .frame(height: height)
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 40, height: 1)
                ForEach(Array(LabToday.week.enumerated()), id: \.offset) { index, morning in
                    let isToday = index == LabToday.week.count - 1
                    Text(isToday ? "TODAY" : "\(morning.day)")
                        .font(.system(size: 9, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? .primary : .tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var notes: LabNotes {
        LabNotes(
            title: "K · Week, History's chart",
            idea: "History's own chart and readout, cut to a week: the same box on top (today's figures against a 7- or 30-day average, the same pills), the same marks and chips below with today labelled. Budgets as health bars.",
            pros: [
                "Today is literally a page of History with today on the end — nothing to learn twice.",
                "Keeps the shape of the week, which J and L give up.",
                "The pills answer 'compared with what' in the place you'd look for it.",
            ],
            cons: [
                "The most to read of the three.",
                "Seven faded columns plus today's is still a chart that needs decoding at 6:30.",
            ],
            take: "Right if you actually use the week on waking. If you only glance at the week on History, pick J or L."
        )
    }
}

// MARK: - Today L · Health bars first

/// The budgets lead. Two large health bars — the one draining now marked —
/// then History's readout as a two-row table, TODAY against USUAL, and the
/// button. No chart at all: the page answers "how much slack is left, and
/// how is today going", and the drawing lives on History.
private struct TodayHealthFirstLab: View {
    @State private var moment = LabMoment.inBed

    var body: some View {
        LabFixedScreen(notes: notes) {
            VStack(alignment: .leading, spacing: 0) {
                LabMomentPicker(moment: $moment)
                LabDateLine().padding(.top, 14)
                LabLabel("This week's slack").padding(.top, 26)
                labBudgets(moment, large: true).padding(.top, 14)
                table.padding(.top, 30)
                HStack {
                    Spacer()
                    LabLabel("All mornings ›", color: .primary, size: 9)
                }
                .padding(.top, 10)
                Spacer(minLength: 14)
            }
        } bottom: {
            LabCTA(title: LabToday.cta(moment)).padding(.horizontal, 22).padding(.bottom, 10)
        }
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Color.clear.frame(width: 58, height: 1)
                header("Woke"); header("To start"); header("Routine")
            }
            ReceiptRule()
            HStack(alignment: .firstTextBaseline) {
                rowLabel("Today", color: .primary)
                value(LabFigures.woke(moment))
                value(LabFigures.toStart(moment))
                value(LabFigures.routine(moment))
            }
            HStack(alignment: .firstTextBaseline) {
                rowLabel("Usual", color: Color(.tertiaryLabel))
                plain("11:22"); plain("33 MIN"); plain("27 MIN")
            }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.6)
            .foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func rowLabel(_ text: String, color: Color) -> some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.6)
            .foregroundStyle(color).frame(width: 58, alignment: .leading)
    }
    private func value(_ f: LabFigures.Figure) -> some View {
        Text(f.value).font(analogFont(19)).monospacedDigit().foregroundStyle(f.color)
            .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.identity)
    }
    private func plain(_ text: String) -> some View {
        Text(text).font(analogFont(19)).monospacedDigit().foregroundStyle(Color(.tertiaryLabel))
            .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notes: LabNotes {
        LabNotes(
            title: "L · Health bars first",
            idea: "Lead with the two things that can still change this morning: how much snooze and activation slack is left this week, as draining health bars. Then today against usual as a two-row table in History's register. No chart.",
            pros: [
                "The least to read. Two bars and six numbers.",
                "The bars are the motivation: watching snooze drain from bed is a reason to get up — and it drains, it doesn't pile up a debt.",
                "Today vs usual as a table is compared at a glance, column by column.",
            ],
            cons: [
                "No picture of the morning or the week on the landing page at all.",
                "On a bad week both bars are empty and red by Wednesday, and stay that way.",
            ],
            take: "The calmest. Pair it with History for the drawing. If the empty-by-Wednesday problem bites, the bars could reset daily instead of weekly."
        )
    }
}

#endif
