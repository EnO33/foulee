import FouleeKit
import Foundation
import Testing
@testable import Foulee

@Suite("Outing merge store")
struct OutingMergeStoreTests {
    private static let noon = Date(timeIntervalSince1970: 1_760_961_600)

    /// Runs `body` against a throwaway suite, so nothing leaks into `.standard`.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "OutingMergeStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test("A merge reads back as it was written")
    func roundTrip() throws {
        try withDefaults { defaults in
            let merge = OutingMerge(workoutIDs: [UUID(), UUID()], startedAt: Self.noon)
            OutingMergeStore.write([merge], to: defaults)
            #expect(OutingMergeStore.read(now: Self.noon, from: defaults) == [merge])
        }
    }

    @Test("Nothing written reads as no merge")
    func emptyStore() throws {
        try withDefaults { defaults in
            #expect(OutingMergeStore.read(now: Self.noon, from: defaults).isEmpty)
        }
    }

    @Test("A merge past the retention is dropped from the store")
    func forgetsOldMerges() throws {
        try withDefaults { defaults in
            let old = OutingMerge(workoutIDs: [UUID()], startedAt: Self.noon)
            OutingMergeStore.write([old], to: defaults)
            let later = Self.noon.addingTimeInterval(OutingMerges.retention + 60)

            #expect(OutingMergeStore.read(now: later, from: defaults).isEmpty)
            #expect(OutingMergeStore.read(now: Self.noon, from: defaults).isEmpty)
        }
    }

    /// A second throwaway suite standing for iCloud's store.
    private func withCloud(_ body: (UserDefaults, UserDefaults) throws -> Void) throws {
        let suiteName = "OutingMergeStoreTests-cloud-\(UUID().uuidString)"
        let cloud = try #require(UserDefaults(suiteName: suiteName))
        defer { cloud.removePersistentDomain(forName: suiteName) }
        try withDefaults { defaults in try body(defaults, cloud) }
    }

    @Test("A merge made here reaches a new iPhone, and so does its separation")
    func mergeAndSeparationTravel() throws {
        try withCloud { here, cloud in
            let merge = OutingMerge(workoutIDs: [UUID(), UUID()], startedAt: Self.noon)
            OutingMergeStore.write([merge], to: here, cloud: cloud, now: Self.noon)

            try withDefaults { newPhone in
                #expect(OutingMergeStore.syncWithCloud(cloud, defaults: newPhone) == .pulled)
                #expect(OutingMergeStore.read(now: Self.noon, from: newPhone) == [merge])

                OutingMergeStore.write([], to: here, cloud: cloud, now: Self.noon.addingTimeInterval(60))
                #expect(OutingMergeStore.syncWithCloud(cloud, defaults: newPhone) == .pulled)
                #expect(OutingMergeStore.read(now: Self.noon, from: newPhone).isEmpty)
            }
        }
    }

    @Test("An install that never merged sends nothing to iCloud")
    func emptyInstallDoesNotSeed() throws {
        try withCloud { defaults, cloud in
            #expect(OutingMergeStore.syncWithCloud(cloud, defaults: defaults) == .unchanged)
            #expect(cloud.dictionaryRepresentation().keys.contains { $0.hasPrefix("outings.") } == false)
        }
    }

    @Test("Merges kept before the sync fill an empty iCloud")
    func existingMergesSeed() throws {
        try withCloud { defaults, cloud in
            let merge = OutingMerge(workoutIDs: [UUID()], startedAt: Self.noon)
            OutingMergeStore.write([merge], to: defaults)

            #expect(OutingMergeStore.syncWithCloud(cloud, defaults: defaults) == .pushed)
            try withDefaults { newPhone in
                OutingMergeStore.syncWithCloud(cloud, defaults: newPhone)
                #expect(OutingMergeStore.read(now: Self.noon, from: newPhone) == [merge])
            }
        }
    }
}
