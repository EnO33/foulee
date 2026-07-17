import Foundation
import Testing
@testable import FouleeWatch

@Suite("WatchComplicationCache")
struct WatchComplicationCacheTests {
    /// Runs `body` against a throwaway suite so tests never touch the real
    /// app-group defaults, and always cleans it up afterwards.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "watch-complication-cache-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test("Write then read round-trips a value stamped today")
    func roundTrip() throws {
        try withDefaults { defaults in
            let now = Date.now
            WatchComplicationCache.write(4_200, for: "steps", now: now, to: defaults)
            #expect(WatchComplicationCache.read(for: "steps", now: now, from: defaults) == 4_200)
        }
    }

    @Test("A value stamped yesterday reads as nil today")
    func dayGuard() throws {
        try withDefaults { defaults in
            let now = Date.now
            let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
            WatchComplicationCache.write(4_200, for: "steps", now: yesterday, to: defaults)
            #expect(WatchComplicationCache.read(for: "steps", now: now, from: defaults) == nil)
        }
    }

    @Test("A legitimate zero is stored and read back as zero, not nil")
    func legitimateZero() throws {
        try withDefaults { defaults in
            let now = Date.now
            WatchComplicationCache.write(0, for: WatchComplicationCache.waterKey, now: now, to: defaults)
            let read = WatchComplicationCache.read(for: WatchComplicationCache.waterKey, now: now, from: defaults)
            #expect(read == 0)
        }
    }

    @Test("Reading before any write returns nil")
    func emptyReadsNil() throws {
        try withDefaults { defaults in
            #expect(WatchComplicationCache.read(for: "steps", from: defaults) == nil)
        }
    }

    @Test("Metric keys are independent")
    func keysAreIndependent() throws {
        try withDefaults { defaults in
            let now = Date.now
            WatchComplicationCache.write(30, for: "minutes", now: now, to: defaults)
            #expect(WatchComplicationCache.read(for: "distance", now: now, from: defaults) == nil)
        }
    }

    @Test("Suites are isolated: a write in one is invisible in another")
    func suiteIsolation() throws {
        try withDefaults { first in
            try withDefaults { second in
                let now = Date.now
                WatchComplicationCache.write(1_500, for: "calories", now: now, to: first)
                #expect(WatchComplicationCache.read(for: "calories", now: now, from: second) == nil)
                #expect(WatchComplicationCache.read(for: "calories", now: now, from: first) == 1_500)
            }
        }
    }

    @Test("Corrupt stored data reads as nil instead of crashing")
    func corruptDataReadsNil() throws {
        try withDefaults { defaults in
            // Same key scheme WatchComplicationCache uses; garbage simulates
            // a value truncated or written by a broken build.
            defaults.set(Data("not json".utf8), forKey: "watch.complication.cache.steps")
            #expect(WatchComplicationCache.read(for: "steps", from: defaults) == nil)
        }
    }
}
