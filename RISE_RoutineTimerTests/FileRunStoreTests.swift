//
//  FileRunStoreTests.swift
//  RISE_RoutineTimerTests
//
//  The property that matters: clearing the run has to be durable straight
//  away. It used to live in UserDefaults, where a pending removal could be
//  lost when the process died, and an ended routine came back on next launch.
//

import XCTest
@testable import RISE_RoutineTimer

final class FileRunStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeRun() -> RoutineRun {
        RoutineRun(
            steps: [RunStep(title: "Dua", durationSeconds: 300, autoNext: false)],
            phase: .running,
            currentIndex: 0,
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000_000),
            endedAt: nil,
            stepAccumulated: 0,
            stepResumedAt: Date(timeIntervalSinceReferenceDate: 1_000_000),
            pausedAt: nil,
            totalPausedSeconds: 0,
            results: [],
            overtimeAnnounced: false
        )
    }

    func testSavesAndLoadsARun() {
        let store = FileRunStore(directory: directory, legacyDefaults: nil)
        store.save(makeRun())
        XCTAssertEqual(store.load()?.steps.first?.title, "Dua")
    }

    /// The regression this store exists for.
    func testClearingIsVisibleToAFreshStoreImmediately() {
        let store = FileRunStore(directory: directory, legacyDefaults: nil)
        store.save(makeRun())
        store.save(nil)

        // A brand new store stands in for the next launch of the app.
        let afterRelaunch = FileRunStore(directory: directory, legacyDefaults: nil)
        XCTAssertNil(afterRelaunch.load())
    }

    func testLoadIsNilWhenNothingWasEverSaved() {
        XCTAssertNil(FileRunStore(directory: directory, legacyDefaults: nil).load())
    }

    // MARK: - Migration off UserDefaults

    func testMigratesARunLeftBehindByAnOlderBuild() throws {
        let defaults = UserDefaults(suiteName: "FileRunStoreTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().description) }
        defaults.set(try JSONEncoder().encode(makeRun()), forKey: "activeRoutineRun")

        let store = FileRunStore(directory: directory, legacyDefaults: defaults)
        XCTAssertEqual(store.load()?.steps.first?.title, "Dua")
        // Taken once, then forgotten, so it can never resurface.
        XCTAssertNil(defaults.data(forKey: "activeRoutineRun"))
    }

    /// The migration must not fire twice. Ending a routine deletes the run
    /// file, and if "already migrated" were implied by that file existing, the
    /// next launch would restore the run that was just ended.
    func testLegacyRunIsNotRestoredAgainAfterBeingEnded() throws {
        let defaults = UserDefaults(suiteName: "FileRunStoreTests.\(UUID().uuidString)")!
        defaults.set(try JSONEncoder().encode(makeRun()), forKey: "activeRoutineRun")

        // Launch one: the old run is picked up.
        XCTAssertNotNil(FileRunStore(directory: directory, legacyDefaults: defaults).load())

        // The user ends it. Pretend UserDefaults never commits the removal,
        // which is what actually happens when the process is killed.
        defaults.set(try JSONEncoder().encode(makeRun()), forKey: "activeRoutineRun")
        FileRunStore(directory: directory, legacyDefaults: defaults).save(nil)
        defaults.set(try JSONEncoder().encode(makeRun()), forKey: "activeRoutineRun")

        // Launch two: it must stay gone.
        XCTAssertNil(FileRunStore(directory: directory, legacyDefaults: defaults).load())
    }

    func testSavingClearsTheOldUserDefaultsCopy() throws {
        let defaults = UserDefaults(suiteName: "FileRunStoreTests.\(UUID().uuidString)")!
        defaults.set(try JSONEncoder().encode(makeRun()), forKey: "activeRoutineRun")

        let store = FileRunStore(directory: directory, legacyDefaults: defaults)
        store.save(nil)
        XCTAssertNil(defaults.data(forKey: "activeRoutineRun"))
        XCTAssertNil(store.load())
    }
}
