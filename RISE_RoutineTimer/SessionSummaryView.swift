//
//  SessionSummaryView.swift
//  RISE_RoutineTimer
//
//  Shown as a sheet the moment a routine finishes.
//

import SwiftData
import SwiftUI

struct SessionSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RoutineSession.startedAt, order: .reverse) private var sessions: [RoutineSession]

    let result: SessionResult

    private var stats: RoutineStats {
        RoutineStats(sessions: sessions.map(\.result))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                    Divider().padding(.bottom, 8)

                    ForEach(Array(result.steps.enumerated()), id: \.offset) { _, step in
                        StepResultRow(step: step)
                    }

                    if let comparison {
                        Divider().padding(.vertical, 12)
                        Text(comparison)
                            .font(analogFont(16))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Routine Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("DONE")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(TimeFormatting.clockTime(from: result.activeSeconds))
                    .font(analogFont(44))
            }

            HStack {
                Text("Started \(TimeFormatting.shortClockTime(from: result.startedAt))")
                Spacer()
                Text(TimeFormatting.scheduleDeltaText(from: result.deltaSeconds))
            }
            .font(analogFont(16))
            .foregroundStyle(.secondary)

            if result.pausedSeconds >= 60 {
                Text("Paused \(TimeFormatting.durationText(from: result.pausedSeconds))")
                    .font(analogFont(16))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var comparison: String? {
        let stats = stats
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
}

/// Planned vs actual for one step, with a bar that fills to the planned
/// width and overflows (in secondary color) when the step ran over.
struct StepResultRow: View {
    let step: StepResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(analogFont(20))
                    .lineLimit(1)
                Spacer()
                Text(TimeFormatting.clockTime(from: step.actualSeconds))
                    .font(analogFont(20))
                Text(deltaText)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }

            GeometryReader { geo in
                let scale = geo.size.width / Double(max(step.plannedSeconds, step.actualSeconds, 1))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: Double(step.plannedSeconds) * scale)
                    Capsule()
                        .fill(step.deltaSeconds > 0 ? Color.secondary : Color.primary)
                        .frame(width: max(3, Double(step.actualSeconds) * scale))
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 8)
    }

    private var deltaText: String {
        if step.autoAdvanced { return "AUTO" }
        if abs(step.deltaSeconds) < 1 { return "ON PLAN" }
        return "\(step.deltaSeconds < 0 ? "−" : "+")\(TimeFormatting.clockTime(from: step.deltaSeconds))"
    }
}
