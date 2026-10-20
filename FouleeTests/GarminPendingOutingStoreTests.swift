import FouleeKit
import Foundation
import Testing
@testable import Foulee

@Suite("Garmin pending outing store")
struct GarminPendingOutingStoreTests {
    private static let noon = Date(timeIntervalSince1970: 1_760_961_600)

    private static let outing = GarminSessionSummary(
        activity: .running,
        startedAt: noon,
        endedAt: noon.addingTimeInterval(1_800),
        durationSeconds: 1_800,
        distanceMeters: 5_000,
        steps: 5_200
    )

    /// Runs `body` against a throwaway suite, so nothing leaks into `.standard`.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "GarminPendingOutingStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test("A summary delivered twice is kept once, across reads")
    func addsOnce() throws {
        try withDefaults { defaults in
            GarminPendingOutingStore.add(Self.outing, to: defaults)
            GarminPendingOutingStore.add(Self.outing, to: defaults)
            #expect(GarminPendingOutingStore.read(from: defaults) == [Self.outing])
        }
    }

    @Test("Once Santé has the outing, the store lets it go")
    func dropsCoveredOutings() throws {
        try withDefaults { defaults in
            GarminPendingOutingStore.add(Self.outing, to: defaults)
            let later = Self.noon.addingTimeInterval(7_200)
            #expect(GarminPendingOutingStore.remaining(healthKitWorkouts: [], now: later, defaults: defaults) == [Self.outing])

            let garminConnect = ActiveMinutes.WorkoutInterval(start: Self.noon, duration: 1_790)
            #expect(GarminPendingOutingStore.remaining(healthKitWorkouts: [garminConnect], now: later, defaults: defaults).isEmpty)
            #expect(GarminPendingOutingStore.read(from: defaults).isEmpty)
        }
    }
}
