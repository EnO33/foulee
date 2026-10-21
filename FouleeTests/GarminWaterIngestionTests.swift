import FouleeKit
import Foundation
import Testing
@testable import Foulee

@Suite("Garmin water ingestion")
struct GarminWaterIngestionTests {
    private static let noon = Date(timeIntervalSince1970: 1_760_961_600)
    private static let first = GarminWaterGlass(id: "a", loggedAt: noon, milliliters: 250)
    private static let second = GarminWaterGlass(id: "b", loggedAt: noon.addingTimeInterval(600), milliliters: 330)

    nonisolated private struct Refused: Error {}

    /// Runs `body` against a throwaway suite, so nothing leaks into `.standard`.
    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suiteName = "GarminWaterIngestionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try await body(defaults)
    }

    @Test("A glass delivered twice waits once")
    func keptOnce() async throws {
        try await withDefaults { defaults in
            GarminWaterStore.add(Self.first, to: defaults)
            GarminWaterStore.add(Self.first, to: defaults)
            #expect(GarminWaterStore.read(from: defaults) == [Self.first])
        }
    }

    @Test("Each glass is written at its time, under its identifier, then let go")
    func writesThenForgets() async throws {
        try await withDefaults { defaults in
            GarminWaterStore.add(Self.first, to: defaults)
            GarminWaterStore.add(Self.second, to: defaults)
            let written = LockedRef<[String]>([])
            var healthKit = HealthKitClient.testValue
            healthKit.logSyncedWater = { milliliters, date, syncIdentifier in
                written.set(written.value + ["\(syncIdentifier) \(milliliters) \(date.timeIntervalSince1970)"])
            }

            await GarminWaterIngestion.drain(healthKit: healthKit, defaults: defaults)

            #expect(written.value == [
                "garmin.water.a 250 1760961600.0",
                "garmin.water.b 330 1760962200.0",
            ])
            #expect(GarminWaterStore.read(from: defaults).isEmpty)
        }
    }

    @Test("A glass Santé refuses waits for the next pass, and so do those after it")
    func refusalKeepsTheRest() async throws {
        try await withDefaults { defaults in
            GarminWaterStore.add(Self.first, to: defaults)
            GarminWaterStore.add(Self.second, to: defaults)
            let refused = Self.second.syncIdentifier
            var healthKit = HealthKitClient.testValue
            healthKit.logSyncedWater = { _, _, syncIdentifier in
                if syncIdentifier == refused { throw Refused() }
            }

            await GarminWaterIngestion.drain(healthKit: healthKit, defaults: defaults)

            #expect(GarminWaterStore.read(from: defaults) == [Self.second])
        }
    }
}
