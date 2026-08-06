import Dependencies
import Foundation
import Testing
@testable import Foulee

/// The phone's half of issue #223: what a session started from the Today
/// screen is stamped with, and how that choice reaches the wrist.
///
/// Every hop below could be reverted with the whole suite green before these
/// existed — the preference resolving to an activity, the activity mode riding
/// in the Watch payload, and the settings change being noticed at all. The one
/// hop no test can hold is the `HKWorkoutConfiguration` itself
/// (`HealthKitClient.liveValue` builds a real `HKWorkoutBuilder`); it is
/// covered by `SessionActivityTests.healthKitMapping` on one side and
/// `ActiveWalkStoreTests.stopSavesTheStartedActivity` on the other, which meet
/// at `WalkSession.activity`.
@Suite("TodayStore activity")
struct TodayStoreActivityTests {
    /// Runs `body` with preferences backed by a throwaway suite, so nothing
    /// leaks into `.standard` or between suites running in parallel.
    @MainActor
    private func withPreferences(_ body: (UserPreferences) async throws -> Void) async throws {
        let suiteName = "TodayStoreActivityTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try await body(UserPreferences(defaults: defaults))
    }

    @Test("A running user starts a run, a walking user a walk")
    @MainActor
    func sessionActivityFollowsThePreference() async throws {
        try await withPreferences { preferences in
            let store = TodayStore()

            preferences.activityMode = .walking
            store.apply(preferences: preferences)
            #expect(store.sessionActivity == .walking)

            // This is what `TodayScreen` hands `ActiveWalkScreen`, which hands
            // it to the session, which the live client turns into
            // `HKWorkoutConfiguration.activityType`. Before #223 the phone
            // wrote `.walking` here whatever the user had chosen.
            preferences.activityMode = .running
            store.apply(preferences: preferences)
            #expect(store.sessionActivity == .running)

            // "Les deux" has no per-session picker until #224 — see
            // `SessionActivityTests.bothFallsBackToWalking`.
            preferences.activityMode = .both
            store.apply(preferences: preferences)
            #expect(store.sessionActivity == .walking)
        }
    }

    @Test("The Watch payload carries the mode, not a default")
    @MainActor
    func watchPayloadCarriesTheActivityMode() async throws {
        try await withDependencies {
            // Publication reads the clock unconditionally since #214.
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = StreakTestSupport.windowed {
                StreakTestSupport.walkedDays([0])
            }
        } operation: {
            try await withPreferences { preferences in
                preferences.activeDays = Set(Weekday.allCases)
                preferences.activityMode = .running
                let store = TodayStore()
                store.apply(preferences: preferences)
                await store.refresh()

                // The only channel the watch has: it owns no settings screen,
                // so a payload that defaulted this field leaves the wrist
                // stamping walks forever, whatever the phone is set to.
                let publication = try #require(store.widgetPublication(stored: nil))
                #expect(publication.watchPayload?.activityMode == .running)
            }
        }
    }

    @Test("The app-group snapshot carries the mode, so the widgets can draw it")
    @MainActor
    func widgetSnapshotCarriesTheActivityMode() async throws {
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = StreakTestSupport.windowed {
                StreakTestSupport.walkedDays([0])
            }
        } operation: {
            try await withPreferences { preferences in
                preferences.activeDays = Set(Weekday.allCases)
                preferences.activityMode = .running
                let store = TodayStore()
                store.apply(preferences: preferences)
                await store.refresh()

                // Same argument as the watch payload above, for the iPhone
                // widgets: the widget process cannot read `UserDefaults
                // .standard`, so this snapshot is its only sight of the
                // preference. Without the field, a runner's Home Screen keeps
                // showing whatever glyph was hardcoded (issue #222).
                let publication = try #require(store.widgetPublication(stored: nil))
                #expect(publication.snapshot.activityMode == .running)

                // And it is not carried forward from what was there before: a
                // mode is mirrored, never measured, so a stored snapshot from
                // an older preference must not win.
                let stale = WidgetSnapshot.placeholder
                #expect(stale.activityMode == .walking)
                let republished = try #require(store.widgetPublication(stored: stale))
                #expect(republished.snapshot.activityMode == .running)
            }
        }
    }

    @Test("Switching only the activity mode counts as a change worth publishing")
    @MainActor
    func changingOnlyTheActivityModeIsNoticed() async throws {
        try await withPreferences { preferences in
            preferences.activityMode = .walking
            let store = TodayStore()
            store.apply(preferences: preferences)
            #expect(store.activityMode == .walking)

            // Nothing else moves: same goals, same days, same window, same
            // hydration. The mode moves no counter — it only picks the glyph
            // and the session's activity type — so a publish is the only
            // effect a change of it can have, and `hasChanged` is what allows
            // one. Without this clause the user switches to "course" in
            // Réglages, taps start on the watch, and still records a walk
            // until some unrelated refresh happens to push a payload.
            preferences.activityMode = .running
            #expect(store.hasChanged(preferences: preferences))

            store.apply(preferences: preferences)
            #expect(store.activityMode == .running)
            #expect(store.sessionActivity == .running)
            // And it settles: a preference set that already matches publishes
            // nothing.
            #expect(!store.hasChanged(preferences: preferences))
        }
    }
}
