import FouleeKit
import Foundation
import Testing
@testable import FouleeWatch

/// « Commencer une sortie » on the watch (issue #607): a named sport starts
/// it, and an empty one does what « Démarrer » does with the synced mode.
@Suite("Watch start outing intent")
struct WatchStartOutingIntentTests {
    /// A throwaway suite, like `WatchStartActivityTests`: the real one is the
    /// shared app group, which every other suite reads.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "watch-start-outing-intent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func payload(_ mode: ActivityMode) -> WatchSyncPayload {
        WatchSyncPayload(streak: 3, minutesGoal: 20, stepsGoal: 6_000, activityMode: mode)
    }

    @Test("A named sport wins over the synced mode")
    @MainActor
    func aNamedSportWins() throws {
        try withDefaults { defaults in
            WatchSyncStore.write(payload(.walking), to: defaults)
            #expect(StartOutingIntent.startIntent(for: .running, syncedTo: defaults) == .start(.running))
        }
    }

    @Test("No sport named starts the synced one")
    @MainActor
    func noSportFollowsTheMode() throws {
        try withDefaults { defaults in
            WatchSyncStore.write(payload(.running), to: defaults)
            #expect(StartOutingIntent.startIntent(for: nil, syncedTo: defaults) == .start(.running))
        }
    }

    /// The stamp in Santé is permanent (#223): « les deux » asks on the wrist.
    @Test("No sport named with « les deux » asks")
    @MainActor
    func noSportWithBothAsks() throws {
        try withDefaults { defaults in
            WatchSyncStore.write(payload(.both), to: defaults)
            #expect(StartOutingIntent.startIntent(for: nil, syncedTo: defaults) == .ask)
        }
    }

    @Test("The Action button offers one workout per sport")
    func theActionButtonOffersBothSports() {
        let styles = StartWorkoutOutingIntent.suggestedWorkouts.map(\.workoutStyle.activity)
        #expect(styles == [.walking, .running])
    }
}
