//
//  HistoryView.swift
//  RISE_RoutineTimer
//
//  The "History" tab: how the routine has been going, and what to change.
//  One routine at a time — MORNING | NIGHT at the top — since a night run is
//  not a slow morning. The night has no wake and nothing to activate from,
//  so its accountability is one number: how late it started against its
//  goal. That is drawn with the morning's own mark, cap at the start.
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var allSessions: [RoutineSession]
    @Query private var logs: [MorningLog]

    @AppStorage(MorningSettings.targetWakeKey) private var targetWakeMinutes = MorningSettings.defaultTargetWakeMinutes
    @AppStorage(MorningSettings.snoozeBudgetKey) private var snoozeBudget = MorningSettings.defaultSnoozeBudget
    @AppStorage(MorningSettings.activationBudgetKey) private var activationBudget = MorningSettings.defaultActivationBudget
    @AppStorage(NightSettings.targetStartKey) private var nightTargetStart = NightSettings.defaultTargetStartMinutes

    /// Every step of both routines; the suggestions are for the one showing.
    let allSteps: [RoutineStep]

    /// Which routine the page is about. Held as the raw value so the shared
    /// switch can bind to it the way it binds to the Run tab's setting.
    @State private var kindRaw: String

    init(steps: [RoutineStep], initialKind: RoutineKind = .morning) {
        allSteps = steps
        _kindRaw = State(initialValue: initialKind.rawValue)
    }

    private var kind: RoutineKind { RoutineKind(rawValue: kindRaw) ?? .morning }
    private var steps: [RoutineStep] { allSteps.routine(kind) }
    private var sessions: [RoutineSession] { allSessions.filter { $0.kind == kind } }

    @State private var appliedSuggestionIDs: Set<UUID> = []
    /// A past session opened in the same summary sheet shown when a run ends.
    @State private var viewingSession: SessionResult?
    /// How many sessions the list shows. A page of history is read for the
    /// chart and the last few mornings; forty rows of sessions made it a
    /// scroll to nowhere. SHOW MORE at the foot adds a page at a time.
    @State private var visibleSessionCount = Self.sessionPage
    /// Whether every suggestion is out, or just the biggest few.
    @State private var showsAllSuggestions = false

    static let sessionPage = 5
    static let suggestionPreview = 3

    private var stats: RoutineStats {
        RoutineStats(sessions: sessions.map(\.result))
    }

    /// The morning's records come from the wake log joined with its runs;
    /// the night's from its runs alone, each run's start standing as its
    /// "wake" and scored against the night's start goal.
    private var morningMetrics: MorningMetrics {
        switch kind {
        case .morning:
            return MorningMetrics(
                records: MorningRecord.join(logs: logs, sessions: sessions),
                settings: MorningSettings(
                    targetWakeMinutes: targetWakeMinutes,
                    snoozeBudgetMinutes: snoozeBudget,
                    activationBudgetMinutes: activationBudget
                ),
                kind: .morning
            )
        case .night:
            return MorningMetrics(
                records: MorningRecord.joinNights(sessions: sessions),
                settings: MorningSettings(targetWakeMinutes: nightTargetStart),
                kind: .night
            )
        }
    }

    private var isEmpty: Bool {
        sessions.isEmpty && (kind == .night || logs.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            RoutineKindSwitch(selected: $kindRaw)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if isEmpty {
                ContentUnavailableView(
                    kind == .night ? "No Nights Yet" : "No Mornings Yet",
                    systemImage: kind.symbol,
                    description: Text("Finish a \(kind.noun) routine and it will show up here.")
                )
            } else {
                List {
                    MorningChartsView(metrics: morningMetrics) { startedAt in
                        viewingSession = sessions.first { $0.startedAt == startedAt }?.result
                    }
                    insightsSection
                    suggestionsSection
                    sessionsSection
                }
                // The switch above already provides the breathing room the
                // list would otherwise add at its top.
                .contentMargins(.top, 0, for: .scrollContent)
            }
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: kind) { _, _ in
            appliedSuggestionIDs = []
            visibleSessionCount = Self.sessionPage
            showsAllSuggestions = false
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            // The one all-time figure that survived the stat tiles. It is
            // the same badge the Run tab wears, in the same corner.
            if streak >= 1 {
                ToolbarItem(placement: .topBarTrailing) { StreakBadge(days: streak) }
            }
        }
        .sheet(item: $viewingSession) { result in
            SessionSummaryView(result: result, context: .history)
        }
    }

    private var streak: Int { stats.currentStreak() }

    // MARK: - Sections

    // The four stat tiles (average, best, average start, streak) that used
    // to lead this page are gone. They were all-time figures over full runs
    // to the second, sitting above a chart readout that averaged the
    // fortnight on screen in whole minutes — two answers to what looked like
    // one question, and neither said which window it covered. The readout
    // stayed, grew an ALL / 7 DAYS / 30 DAYS switch, and the streak moved to
    // the toolbar.

    /// Moved off the Today tab when that became a single screen. It belongs
    /// beside the baselines it is drawn from anyway.
    private var insightsSection: some View {
        Section("Insights") {
            ForEach(morningMetrics.insights(), id: \.self) { line in
                Text(line).font(.subheadline)
            }
        }
    }

    /// One line per step, biggest change first, three at a time. Each used
    /// to be a paragraph with its own button; sixteen steps of that was the
    /// longest thing on the page.
    @ViewBuilder
    private var suggestionsSection: some View {
        let suggestions = stats.suggestions(for: steps.map(RunStep.init))
            .filter { !appliedSuggestionIDs.contains($0.stepID) }
            .sorted { abs($0.suggestedSeconds - $0.plannedSeconds) > abs($1.suggestedSeconds - $1.plannedSeconds) }
        let shown = showsAllSuggestions ? suggestions : Array(suggestions.prefix(Self.suggestionPreview))
        let hidden = suggestions.count - shown.count

        if !suggestions.isEmpty {
            Section {
                ForEach(shown) { suggestion in
                    SuggestionRow(suggestion: suggestion) {
                        apply(suggestion)
                    }
                }
                if hidden > 0 {
                    showMoreRow("\(hidden) MORE") { showsAllSuggestions = true }
                }
            } header: {
                Text("Suggestions")
            } footer: {
                Text("What each step usually takes against its plan, over normally timed runs. Tap the new time to apply it.")
            }
        }
    }

    private var sessionsSection: some View {
        let shown = Array(sessions.prefix(visibleSessionCount))
        let hidden = sessions.count - shown.count

        return Section("Sessions") {
            ForEach(shown) { session in
                Button {
                    viewingSession = session.result
                } label: {
                    SessionRow(session: session)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteSessions)

            if hidden > 0 {
                showMoreRow("SHOW \(min(hidden, Self.sessionPage)) MORE · \(hidden) LEFT") {
                    visibleSessionCount += Self.sessionPage
                }
            }
        }
    }

    /// The list's "there is more" row, in the tracked-caps register.
    private func showMoreRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            HStack {
                Spacer()
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func apply(_ suggestion: StepSuggestion) {
        guard let step = steps.first(where: { $0.stepID == suggestion.stepID }) else { return }
        withAnimation {
            step.durationSeconds = suggestion.suggestedSeconds
            appliedSuggestionIDs.insert(suggestion.stepID)
        }
        save()
    }

    private func deleteSessions(at offsets: IndexSet) {
        // Offsets are into the shown prefix, which is a prefix of `sessions`,
        // so the indices line up.
        for index in offsets where sessions.indices.contains(index) {
            modelContext.delete(sessions[index])
        }
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Could not save history change: \(error)")
        }
    }

}

/// One line: the step, what it is planned at and usually takes, and the new
/// time as the button. It was a title, a sentence and a button stacked —
/// three lines per step — and read as a page of its own.
private struct SuggestionRow: View {
    let suggestion: StepSuggestion
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(analogFont(17))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Button(action: apply) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(TimeFormatting.durationText(from: suggestion.suggestedSeconds).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary, in: Capsule())
                .foregroundStyle(Color(.systemBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(suggestion.title) to \(TimeFormatting.durationText(from: suggestion.suggestedSeconds))")
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        let planned = TimeFormatting.clockTime(from: suggestion.plannedSeconds)
        let usual = TimeFormatting.clockTime(from: suggestion.averageActualSeconds)
        return "PLAN \(planned) · USUALLY \(usual) · \(suggestion.sampleCount) RUNS"
    }
}

private struct SessionRow: View {
    let session: RoutineSession

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    var body: some View {
        let breakdown = SessionBreakdown(steps: session.stepRecords)
        // What makes this run not a full one, if anything. On a line of
        // their own: beside the time range, three of them ran off the row.
        let tags = (session.completed ? [] : ["ENDED EARLY"]) + breakdown.partialTags

        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dayFormatter.string(from: session.startedAt))
                    .font(.subheadline)
                Text(TimeFormatting.clockRange(from: session.startedAt, to: session.endedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(TimeFormatting.clockTime(from: session.activeSeconds))
                    .font(analogFont(22))
                // The steps that happened, against their plans — the same
                // number the summary opens with. The raw figure called a
                // skipped coffee "12:00 ahead".
                Text(TimeFormatting.scheduleDeltaText(from: breakdown.pacedDeltaSeconds))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
        }
        .padding(.vertical, 4)
    }
}
