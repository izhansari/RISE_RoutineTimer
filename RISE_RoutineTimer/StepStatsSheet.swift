//
//  StepStatsSheet.swift
//  RISE_RoutineTimer
//
//  How one step usually goes, opened from the arrow on a selected row of the
//  Run tab's idle list. Same boxed receipt sections as the run sheet.
//

import SwiftData
import SwiftUI

struct StepStatsSheet: View {
    @Environment(\.modelContext) private var modelContext

    let step: RoutineStep
    let stats: RoutineStats

    @State private var detent: PresentationDetent = .medium

    var body: some View {
        let history = stats.history(forStepID: step.stepID)
        let suggestion = stats.suggestions(for: [step].map(RunStep.init)).first

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ReceiptSheetTitle(title: step.title)
                    .padding(.top, 24)
                    .padding(.bottom, 22)

                ReceiptSection("Plan") {
                    ReceiptStatRow("Duration", TimeFormatting.clockTime(from: step.durationSeconds))
                    ReceiptRule()
                    ReceiptStatRow("Advance", step.autoNext ? "AUTO" : "MANUAL")
                }

                ReceiptSection("Recent runs") {
                    if history.hasEvidence {
                        recentRows(history)
                    } else {
                        Text("This step has not been run yet.")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                }

                if let suggestion {
                    ReceiptSection("Suggestion") {
                        HStack(spacing: 14) {
                            Text("Usually takes about \(TimeFormatting.clockTime(from: suggestion.averageActualSeconds)). Set it to \(TimeFormatting.clockTime(from: suggestion.suggestedSeconds))?")
                                .font(.system(size: 15))
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ReceiptBarButton(title: "Use") {
                                step.durationSeconds = suggestion.suggestedSeconds
                                try? modelContext.save()
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    @ViewBuilder
    private func recentRows(_ history: StepHistory) -> some View {
        let manualCount = history.manualSamples.count
        if let average = history.averageSeconds {
            ReceiptStatRow("Average", TimeFormatting.clockTime(from: average),
                           detail: "\(manualCount) manual")
            ReceiptRule()
            let delta = average - step.durationSeconds
            ReceiptStatRow("Vs plan", delta == 0 ? "ON PLAN"
                           : "\(delta < 0 ? "−" : "+")\(TimeFormatting.clockTime(from: abs(delta)))")
        } else {
            ReceiptStatRow("Average", "—",
                           detail: step.autoNext ? "auto runs to plan" : "after 2 manual runs")
        }
        if let best = history.bestSeconds {
            ReceiptRule()
            ReceiptStatRow("Best", TimeFormatting.clockTime(from: best))
        }
        if let last = history.lastSeconds {
            ReceiptRule()
            ReceiptStatRow("Last", TimeFormatting.clockTime(from: last))
        }
        ReceiptRule()
        ReceiptStatRow("Skipped", "\(history.skipped)", detail: "of \(history.appearances) runs")
    }
}
