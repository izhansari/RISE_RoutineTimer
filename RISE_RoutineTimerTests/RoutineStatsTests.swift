//
//  RoutineStatsTests.swift
//  RISE_RoutineTimerTests
//

import XCTest
@testable import RISE_RoutineTimer

final class RoutineStatsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ offset: Int, hour: Int = 6, minute: Int = 30) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func session(dayOffset: Int, active: Int, planned: Int = 1320, completed: Bool = true, hour: Int = 6, minute: Int = 30, steps: [StepResult] = []) -> SessionResult {
        let start = day(dayOffset, hour: hour, minute: minute)
        return SessionResult(startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(active)), plannedSeconds: planned, activeSeconds: active, pausedSeconds: 0, completed: completed, steps: steps)
    }

    func testAveragesIgnoreAbandonedSessions() {
        let stats = RoutineStats(sessions: [
            session(dayOffset: 0, active: 1200),
            session(dayOffset: -1, active: 1000),
            session(dayOffset: -2, active: 100, completed: false),
        ], calendar: calendar)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.averageActiveSeconds, 1100)
        XCTAssertEqual(stats.bestActiveSeconds, 1000)
        XCTAssertEqual(stats.latest?.activeSeconds, 1200)
    }

    func testEmptyStats() {
        let stats = RoutineStats(sessions: [], calendar: calendar)
        XCTAssertNil(stats.averageActiveSeconds)
        XCTAssertNil(stats.bestActiveSeconds)
        XCTAssertNil(stats.averageStartSecondsSinceMidnight)
        XCTAssertEqual(stats.currentStreak(today: day(0)), 0)
        XCTAssertNil(stats.recentTrendSeconds())
    }

    func testAverageStartTime() {
        let stats = RoutineStats(sessions: [
            session(dayOffset: 0, active: 1200, hour: 6, minute: 0),
            session(dayOffset: -1, active: 1200, hour: 7, minute: 0),
        ], calendar: calendar)
        XCTAssertEqual(stats.averageStartSecondsSinceMidnight, 6 * 3600 + 30 * 60)
    }

    func testStreakCountsConsecutiveDaysAndToleratesTodayMissing() {
        let sessions = [session(dayOffset: -1, active: 1200), session(dayOffset: -2, active: 1200), session(dayOffset: -3, active: 1200), session(dayOffset: -6, active: 1200)]
        let stats = RoutineStats(sessions: sessions, calendar: calendar)
        XCTAssertEqual(stats.currentStreak(today: day(0, hour: 12)), 3, "today not done yet still counts yesterday's streak")
        XCTAssertEqual(stats.currentStreak(today: day(1)), 0, "streak is broken after a full missed day")

        let withToday = RoutineStats(sessions: sessions + [session(dayOffset: 0, active: 1200)], calendar: calendar)
        XCTAssertEqual(withToday.currentStreak(today: day(0, hour: 12)), 4)
    }

    func testRecentTrend() {
        var sessions: [SessionResult] = []
        for i in 0..<5 { sessions.append(session(dayOffset: -i, active: 1000)) }
        for i in 5..<10 { sessions.append(session(dayOffset: -i, active: 1300)) }
        let stats = RoutineStats(sessions: sessions, calendar: calendar)
        XCTAssertEqual(stats.recentTrendSeconds(), -300)
        XCTAssertNil(RoutineStats(sessions: Array(sessions.prefix(9)), calendar: calendar).recentTrendSeconds())
    }

    func testSuggestionsNeedThreeManualSamplesAndAMeaningfulGap() {
        let stretch = RunStep(title: "Stretch", durationSeconds: 300)
        let wash = RunStep(title: "Wash", durationSeconds: 600, autoNext: false)
        let plan = RunStep(title: "Plan", durationSeconds: 300)

        func record(_ step: RunStep, _ actual: Int, auto: Bool = false) -> StepResult {
            StepResult(stepID: step.id, title: step.title, plannedSeconds: step.durationSeconds, actualSeconds: actual, autoAdvanced: auto)
        }

        var sessions: [SessionResult] = []
        for i in 0..<3 {
            sessions.append(session(dayOffset: -i, active: 1000, steps: [
                record(stretch, 170),            // usually ~1 min early
                record(wash, 640),               // slightly over, within 15%
                record(plan, 300, auto: true),   // auto-advanced, not evidence
            ]))
        }

        let suggestions = RoutineStats(sessions: sessions, calendar: calendar).suggestions(for: [stretch, wash, plan])
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].stepID, stretch.id)
        XCTAssertEqual(suggestions[0].averageActualSeconds, 170)
        XCTAssertEqual(suggestions[0].suggestedSeconds, 180)
        XCTAssertTrue(suggestions[0].isShorter)

        let twoOnly = RoutineStats(sessions: Array(sessions.prefix(2)), calendar: calendar).suggestions(for: [stretch])
        XCTAssertTrue(twoOnly.isEmpty)
    }

    func testRoundedDuration() {
        XCTAssertEqual(RoutineStats.roundedDuration(52), 45)
        XCTAssertEqual(RoutineStats.roundedDuration(170), 180)
        XCTAssertEqual(RoutineStats.roundedDuration(400), 390)
        XCTAssertEqual(RoutineStats.roundedDuration(1000), 1020)
        XCTAssertEqual(RoutineStats.roundedDuration(2), RoutineStep.minimumDurationSeconds)
    }

    // MARK: - Step history

    private func stepResult(_ id: UUID, actual: Int, auto: Bool = false, skipped: Bool = false) -> StepResult {
        StepResult(stepID: id, title: "Dua", plannedSeconds: 300, actualSeconds: actual, autoAdvanced: auto, skipped: skipped)
    }

    func testStepHistorySummarisesManualSamplesSkipsAndAutoAdvances() {
        let id = UUID()
        let stats = RoutineStats(sessions: [
            session(dayOffset: 0, active: 1200, steps: [stepResult(id, actual: 240)]),
            session(dayOffset: -1, active: 1200, steps: [stepResult(id, actual: 360)]),
            session(dayOffset: -2, active: 1200, steps: [stepResult(id, actual: 300, auto: true)]),
            session(dayOffset: -3, active: 1200, steps: [stepResult(id, actual: 20, skipped: true)]),
            session(dayOffset: -4, active: 100, completed: false, steps: [stepResult(id, actual: 1)]),
        ], calendar: calendar)

        let history = stats.history(forStepID: id)
        XCTAssertEqual(history.appearances, 4, "abandoned sessions are not evidence")
        XCTAssertEqual(history.manualSamples, [240, 360], "newest first, manual completions only")
        XCTAssertEqual(history.averageSeconds, 300)
        XCTAssertEqual(history.bestSeconds, 240)
        XCTAssertEqual(history.lastSeconds, 240)
        XCTAssertEqual(history.skipped, 1)
        XCTAssertEqual(history.autoAdvanced, 1)
        XCTAssertTrue(history.hasEvidence)
    }

    func testStepHistoryNeedsTwoManualSamplesForAnAverage() {
        let id = UUID()
        let stats = RoutineStats(sessions: [
            session(dayOffset: 0, active: 1200, steps: [stepResult(id, actual: 250)]),
        ], calendar: calendar)

        let history = stats.history(forStepID: id)
        XCTAssertNil(history.averageSeconds)
        XCTAssertEqual(history.lastSeconds, 250)
        XCTAssertEqual(history.bestSeconds, 250)
        XCTAssertTrue(history.hasEvidence)

        let unknown = stats.history(forStepID: UUID())
        XCTAssertFalse(unknown.hasEvidence)
        XCTAssertEqual(unknown, StepHistory(appearances: 0, manualSamples: [], skipped: 0, autoAdvanced: 0))
    }
}
