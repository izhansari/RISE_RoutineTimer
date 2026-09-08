//
//  RoutineIntents.swift
//  RISE_RoutineTimer
//
//  The two things Shortcuts can ask the app to do. Both run in the app's
//  own process against the same engine and store the views use, so there is
//  no second code path to keep honest.
//
//  The intended automation: when the phone comes off the charger in the
//  morning, run "I'm Awake" (which confirms first, so a false alarm can be
//  waved off), then "Open RISE" — or "Start Morning Routine", which opens
//  the app itself.
//

import AppIntents
import Foundation
import SwiftData

// MARK: - Start the routine

struct StartRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Morning Routine"
    static let description = IntentDescription(
        "Starts the routine timer and opens RISE on the Run tab. Does nothing if a routine is already running."
    )
    static let openAppWhenRun = true

    // The protocol requirement is nonisolated; the engine and store are not.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let engine = AppServices.engine, let container = AppServices.container else {
            throw RoutineIntentError.appNotReady
        }

        if engine.hasActiveRun {
            AppServices.navigation?.selectedTab = .run
            return .result(dialog: "A routine is already running.")
        }

        let descriptor = FetchDescriptor<RoutineStep>(sortBy: [SortDescriptor(\.sortOrder)])
        let steps = try container.mainContext.fetch(descriptor)
        guard !steps.isEmpty else {
            return .result(dialog: "Your routine has no steps yet.")
        }

        if engine.isComplete { engine.reset() }
        engine.start(steps: steps.map(RunStep.init))
        AppServices.navigation?.selectedTab = .run
        return .result(dialog: "Routine started.")
    }
}

// MARK: - I'm awake

struct MarkAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "I'm Awake"
    static let description = IntentDescription(
        "Logs now as the time you woke up. Asks first by default, so an automation that fires by mistake can be waved off. Does not open the app — add Open App after it if you want that."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Ask Before Logging", default: true)
    var askFirst: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Mark me as awake") {
            \.$askFirst
        }
    }

    // The protocol requirement is nonisolated; the engine and store are not.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = AppServices.container else {
            throw RoutineIntentError.appNotReady
        }

        let context = container.mainContext
        let store = MorningLogStore(context: context)
        let logs = try context.fetch(FetchDescriptor<MorningLog>())
        let now = Date()

        if let already = store.log(logs, dayOf: now)?.wakeAt {
            return .result(dialog: "Already marked awake at \(TimeFormatting.shortClockTime(from: already)).")
        }

        if askFirst {
            try await requestConfirmation(
                result: .result(dialog: "Mark you as awake now?"),
                confirmationActionName: .go
            )
        }

        store.recordWake(at: now, existing: logs)
        return .result(dialog: "Marked awake at \(TimeFormatting.shortClockTime(from: now)).")
    }
}

// MARK: - Errors

enum RoutineIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            return "RISE isn't ready yet. Open the app once and try again."
        }
    }
}

// MARK: - App Shortcuts

/// Surfaces both intents in the Shortcuts app and to Siri without the user
/// building anything first.
struct RISEShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRoutineIntent(),
            phrases: [
                "Start my morning routine in \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Start Routine",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: MarkAwakeIntent(),
            phrases: [
                "I'm awake in \(.applicationName)",
                "Log my wake time in \(.applicationName)",
            ],
            shortTitle: "I'm Awake",
            systemImageName: "sun.max"
        )
    }
}
