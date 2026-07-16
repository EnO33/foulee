import Foundation
import Testing
@testable import FouleeWatch

@Suite("WatchSyncStore")
struct WatchSyncStoreTests {
    /// Runs `body` against a throwaway suite so tests never touch the real
    /// app-group defaults, and always cleans it up afterwards.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "watch-sync-store-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test("Write then read round-trips every field")
    func roundTrip() throws {
        try withDefaults { defaults in
            let payload = WatchSyncPayload(
                streak: 7,
                minutesGoal: 25,
                stepsGoal: 9_000,
                hydrationEnabled: true,
                hydrationGoalML: 1_750,
                hydrationGlassML: 300
            )
            WatchSyncStore.write(payload, to: defaults)
            let read = try #require(WatchSyncStore.read(from: defaults))
            #expect(read.streak == 7)
            #expect(read.minutesGoal == 25)
            #expect(read.stepsGoal == 9_000)
            #expect(read.hydrationEnabled)
            #expect(read.hydrationGoalML == 1_750)
            #expect(read.hydrationGlassML == 300)
        }
    }

    @Test("Reading before any sync returns nil, not a default payload")
    func emptyReadsNil() throws {
        try withDefaults { defaults in
            #expect(WatchSyncStore.read(from: defaults) == nil)
        }
    }

    @Test("Corrupt stored data reads as nil instead of crashing")
    func corruptDataReadsNil() throws {
        try withDefaults { defaults in
            // Same key WatchSyncStore uses; garbage simulates a payload
            // truncated or written by a broken build.
            defaults.set(Data("not json".utf8), forKey: "watch.sync.payload")
            #expect(WatchSyncStore.read(from: defaults) == nil)
        }
    }

    @Test("A newer payload overwrites the previous one")
    func overwrite() throws {
        try withDefaults { defaults in
            WatchSyncStore.write(
                WatchSyncPayload(streak: 1, minutesGoal: 20, stepsGoal: 6_000),
                to: defaults
            )
            WatchSyncStore.write(
                WatchSyncPayload(streak: 2, minutesGoal: 30, stepsGoal: 8_000),
                to: defaults
            )
            let read = try #require(WatchSyncStore.read(from: defaults))
            #expect(read.streak == 2)
            #expect(read.minutesGoal == 30)
            #expect(read.stepsGoal == 8_000)
        }
    }

    @Test("Pre-hydration payloads decode with hydration off and defaults")
    func tolerantDecodingOfOldPayloads() throws {
        try withDefaults { defaults in
            // A payload persisted by a build that predates hydration: only the
            // original three keys are present.
            let old = Data(#"{"streak":5,"minutesGoal":20,"stepsGoal":6000}"#.utf8)
            defaults.set(old, forKey: "watch.sync.payload")
            let read = try #require(WatchSyncStore.read(from: defaults))
            #expect(read.streak == 5)
            #expect(!read.hydrationEnabled)
            #expect(read.hydrationGoalML == 2_000)
            #expect(read.hydrationGlassML == 250)
        }
    }
}
