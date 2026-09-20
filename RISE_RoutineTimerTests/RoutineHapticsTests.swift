//
//  RoutineHapticsTests.swift
//  RISE_RoutineTimerTests
//
//  The patterns are plain data, so their shape can be pinned without a
//  Taptic Engine: what they *feel* like still has to be judged on a phone.
//

import CoreHaptics
import XCTest
@testable import RISE_RoutineTimer

final class RoutineHapticsTests: XCTestCase {
    func testPatternsBuild() throws {
        XCTAssertNoThrow(try RoutineHaptics.pattern(RoutineHaptics.stepDone))
        XCTAssertNoThrow(try RoutineHaptics.pattern(RoutineHaptics.routineComplete))
    }

    /// Click, then thud: the second beat has to be quieter *and* duller, or
    /// it reads as a double tap instead of as weight.
    func testStepDoneIsAClickThenASofterThud() {
        let beats = RoutineHaptics.stepDone
        XCTAssertEqual(beats.count, 2)
        XCTAssertEqual(beats[0].time, 0)
        XCTAssertLessThan(beats[1].time, 0.1, "close enough to be one event under the thumb")
        XCTAssertLessThan(beats[1].intensity, beats[0].intensity)
        XCTAssertLessThan(beats[1].sharpness, beats[0].sharpness)
    }

    /// The flourish has to start after the last step's chunk has finished,
    /// and build.
    func testTheFlourishFollowsTheChunkAndRises() {
        let chunkEnds = RoutineHaptics.stepDone.map(\.time).max() ?? 0
        let beats = RoutineHaptics.routineComplete
        XCTAssertGreaterThan(beats[0].time, chunkEnds + 0.1)
        XCTAssertEqual(beats.map(\.time), beats.map(\.time).sorted())
        XCTAssertEqual(beats.map(\.intensity), beats.map(\.intensity).sorted())
        XCTAssertEqual(beats.map(\.sharpness), beats.map(\.sharpness).sorted())
        for beat in RoutineHaptics.stepDone + beats {
            XCTAssertTrue((0...1).contains(beat.intensity) && (0...1).contains(beat.sharpness))
        }
    }
}
