//
//  HistoryView.swift
//  RISE_RoutineTimer
//
//  The "History" tab: how the routine has been going, and what to change.
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]
    @Query private var logs: [MorningLog]

    @AppStorage(MorningSettings.targetWakeKey) private var targetWakeMinutes = MorningSettings.defaultTargetWakeMinutes
    @AppStorage(MorningSettings.snoozeBudgetKey) private var snoozeBudget = MorningSettings.defaultSnoozeBudget
    @AppStorage(MorningSettings.activationBudgetKey) private var activationBudget = MorningSettings.defaultActivationBudget

    let steps: [RoutineStep]

    @State private var appliedSuggestionIDs: Set<UUID> = []

    private var stats: RoutineStats {
        RoutineStats(sessions: sessions.map(\.result))
    }

    private var morningMetrics: MorningMetrics {
        MorningMetrics(
            records: MorningRecord.join(logs: logs, sessions: sessions),
            settings: MorningSettings(
                targetWakeMinutes: targetWakeMinutes,
                snoozeBudgetMinutes: snoozeBudget,
                activationBudgetMinutes: activationBudget
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty && logs.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finish a routine and it will show up here.")
                    )
                } else {
                    List {
                        statsSection
                        MorningChartsView(metrics: morningMetrics)
                        suggestionsSection
                        sessionsSection
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    // MARK: - Sections

    private var statsSection: some View {
        Section {
            let stats = stats
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(label: "AVERAGE", value: stats.averageActiveSeconds.map(TimeFormatting.clockTime) ?? "—")
                StatTile(label: "BEST", value: stats.bestActiveSeconds.map(TimeFormatting.clockTime) ?? "—")
                StatTile(label: "AVG START", value: stats.averageStartSecondsSinceMidnight.map(clockOfDay) ?? "—")
                StatTile(label: "STREAK", value: streakText(stats.currentStreak()))
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        } footer: {
            if let trend = stats.recentTrendSeconds() {
                Text(trendText(trend))
            } else {
                Text("\(stats.count) completed · trend appears after 10 sessions")
            }
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        let suggestions = stats.suggestions(for: steps.map(RunStep.init))
            .filter { !appliedSuggestionIDs.contains($0.stepID) }
        if !suggestions.isEmpty {
            Section("Suggestions") {
                ForEach(suggestions) { suggestion in
                    SuggestionRow(suggestion: suggestion) {
                        apply(suggestion)
                    }
                }
            }
        }
    }

    private var sessionsSection: some View {
        Section("Sessions") {
            ForEach(sessions) { session in
                SessionRow(session: session)
            }
            .onDelete(perform: deleteSessions)
        }
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
        for index in offsets {
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

    // MARK: - Formatting

    private func clockOfDay(_ secondsSinceMidnight: Int) -> String {
        let date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(secondsSinceMidnight))
        return TimeFormatting.shortClockTime(from: date)
    }

    private func streakText(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    private func trendText(_ trend: Int) -> String {
        if abs(trend) < 15 { return "Last 5 sessions: about the same as before." }
        let direction = trend < 0 ? "faster" : "slower"
        return "Last 5 sessions: \(TimeFormatting.durationText(from: abs(trend))) \(direction) than the 5 before."
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(analogFont(30))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SuggestionRow: View {
    let suggestion: StepSuggestion
    let apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestion.title)
                .font(analogFont(20))
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                apply()
            } label: {
                Text("SET TO \(TimeFormatting.durationText(from: suggestion.suggestedSeconds).uppercased())")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary, in: Capsule())
                    .foregroundStyle(Color(.systemBackground))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private var explanation: String {
        let verb = suggestion.isShorter ? "finish it in" : "take"
        return "Planned \(TimeFormatting.durationText(from: suggestion.plannedSeconds)), but you usually \(verb) about \(TimeFormatting.durationText(from: suggestion.averageActualSeconds)) (\(suggestion.sampleCount) sessions)."
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dayFormatter.string(from: session.startedAt))
                    .font(.subheadline)
                HStack(spacing: 8) {
                    Text("Started \(TimeFormatting.shortClockTime(from: session.startedAt))")
                    if !session.completed {
                        Text("ENDED EARLY")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(TimeFormatting.clockTime(from: session.activeSeconds))
                    .font(analogFont(22))
                Text(TimeFormatting.scheduleDeltaText(from: session.result.deltaSeconds))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
