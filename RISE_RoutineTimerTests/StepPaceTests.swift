//
//  StepPaceTests.swift
//  RISE_RoutineTimerTests
//
//  The fill colour is a per-step signal. The property that matters most is
//  that it does NOT carry over between steps — that was the whole complaint
//  about the previous cumulative version.
//

import SwiftUI
import XCTest
@testable import RISE_RoutineTimer

final class StepPaceTests: XCTestCase {
    func testOnTimeWhileInsidePlannedDuration() {
        XCTAssertEqual(StepPace(overtimeSeconds: 0), .onTime)
        XCTAssertEqual(StepPace(overtimeSeconds: -30), .onTime)
    }

    func testAmberAssoonAsAStepRunsOver() {
        XCTAssertEqual(StepPace(overtimeSeconds: 1), .running)
        XCTAssertEqual(StepPace(overtimeSeconds: 119), .running)
    }

    func testRedPastTheThreshold() {
        XCTAssertEqual(StepPace(overtimeSeconds: StepPace.overThresholdSeconds), .over)
        XCTAssertEqual(StepPace(overtimeSeconds: 600), .over)
    }

    func testOnTimeUsesTheChosenThemeColour() {
        for theme in FillTheme.allCases {
            XCTAssertEqual(StepPace.onTime.fillColor(theme: theme), theme.color)
        }
    }

    /// Overtime must look the same whatever colour the user picked, or the
    /// warning stops being recognisable.
    func testOvertimeColoursIgnoreTheTheme() {
        let running = Set(FillTheme.allCases.map { StepPace.running.fillColor(theme: $0) })
        let over = Set(FillTheme.allCases.map { StepPace.over.fillColor(theme: $0) })
        XCTAssertEqual(running.count, 1)
        XCTAssertEqual(over.count, 1)
        XCTAssertNotEqual(running.first, over.first)
    }

    /// No theme may be an amber or a red, otherwise a step running over would
    /// be indistinguishable from one running to plan.
    func testNoThemeCollidesWithTheOvertimeColours() {
        let reserved: Set<Color> = [
            StepPace.running.fillColor(theme: .green),
            StepPace.over.fillColor(theme: .green)
        ]
        for theme in FillTheme.allCases {
            XCTAssertFalse(reserved.contains(theme.color), "\(theme.title) collides with an overtime colour")
        }
    }

    /// The engine reports overtime per step, so moving on clears the state
    /// without the pace type having to remember anything.
    func testPaceIsStatelessAcrossSteps() {
        let duringSlowStep = StepPace(overtimeSeconds: 300)
        let afterMovingOn = StepPace(overtimeSeconds: 0)
        XCTAssertEqual(duringSlowStep, .over)
        XCTAssertEqual(afterMovingOn, .onTime)
    }

    // MARK: - Cumulative label (text only)

    func testCumulativeLabelWording() {
        XCTAssertEqual(RoutinePace.label(deltaSeconds: 0), "ON PLAN")
        XCTAssertEqual(RoutinePace.label(deltaSeconds: 20), "ON PLAN")
        XCTAssertEqual(RoutinePace.label(deltaSeconds: 125), "2:05 BEHIND")
        XCTAssertEqual(RoutinePace.label(deltaSeconds: -90), "1:30 AHEAD")
    }
}

// MARK: - Glyph catalog

final class GlyphCatalogTests: XCTestCase {
    func testSearchMatchesKeywordsNotJustTheGlyph() {
        let results = GlyphCatalog.filtered(by: "gym").flatMap(\.glyphs).map(\.value)
        XCTAssertTrue(results.contains("🏋️"))
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertFalse(GlyphCatalog.filtered(by: "SHOWER").isEmpty)
        XCTAssertFalse(GlyphCatalog.filtered(by: "shower").isEmpty)
    }

    func testEmptyQueryReturnsEverything() {
        XCTAssertEqual(GlyphCatalog.filtered(by: "  ").count, GlyphCatalog.categories.count)
    }

    func testUnmatchedQueryReturnsNoCategories() {
        XCTAssertTrue(GlyphCatalog.filtered(by: "zzzznope").isEmpty)
    }

    /// A duplicate would give the grid two tiles that select the same icon,
    /// and `Identifiable` uses the glyph itself as the id.
    func testGlyphsAreUnique() {
        let all = GlyphCatalog.categories.flatMap(\.glyphs).map(\.value)
        XCTAssertEqual(all.count, Set(all).count)
    }

    /// The model keeps only the first grapheme, so every catalog entry has to
    /// survive that unchanged — including the ZWJ and variation-selector ones.
    func testEveryGlyphSurvivesNormalisation() {
        for glyph in GlyphCatalog.categories.flatMap(\.glyphs) {
            XCTAssertEqual(RoutineStep.normalizedIcon(glyph.value), glyph.value, "\(glyph.value) is altered by normalizedIcon")
        }
    }
}
