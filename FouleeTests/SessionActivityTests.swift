import Foundation
import HealthKit
import Testing
@testable import Foulee

/// First cover for what Foulée stamps a session with in Santé (#223). Nothing
/// asserted either activity literal before: the phone wrote `config.activityType
/// = .walking` and the watch `configuration.activityType = .walking`, and the
/// suite was green with every run recorded as a walk.
///
/// The phone's own write can't be exercised end to end — `HealthKitClient.
/// liveValue` builds a real `HKHealthStore` and `HKWorkoutBuilder`, neither of
/// which works in a test process. So the seam is covered in two halves that
/// meet at `WalkSession.activity`: `ActiveWalkStoreTests` asserts the session
/// reaching the client carries the started activity, and the mapping below
/// asserts what the client turns that into. The watch, whose HealthKit facade
/// *is* injectable, gets the real end-to-end assertion on the configuration
/// (`FouleeWatchTests/WatchWorkoutStoreTests`).
@Suite("Session activity")
struct SessionActivityTests {
    @Test("A run maps to HKWorkoutActivityType.running, a walk to .walking")
    func healthKitMapping() {
        #expect(SessionActivity.running.hkActivityType == .running)
        #expect(SessionActivity.walking.hkActivityType == .walking)
        // Spelled out rather than mapped over `allCases`, which would make the
        // assertion true by construction — the exact trap #217 fell into.
        #expect(SessionActivity.allCases.count == 2)
    }

    // `SessionActivity(mode:)` is gone (#224). It answered "which activity for
    // this mode?" with a value it had to invent for « les deux » — a walk,
    // permanently, for every session such a user recorded. The question now
    // has its own type, which can say « ask »: see `ActivityStartIntentTests`.

    @Test("The two activities are named the way the rest of the app names them")
    func labels() {
        // The same two words as `ActivityMode.label`, `OnboardingActivityView`
        // and the Réglages picker. Spelled out rather than compared to
        // `ActivityMode.label`, which would make both sides free to drift
        // together — the point is the exact string a user reads on the wrist.
        #expect(SessionActivity.walking.label == "Marche")
        #expect(SessionActivity.running.label == "Course")
        #expect(SessionActivity.walking.icon == ActivityGlyph.walk)
        #expect(SessionActivity.running.icon == ActivityGlyph.run)
    }

    @Test("The calorie estimate is activity-aware, and walking is untouched")
    func estimatedCaloriesFollowTheActivity() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var walk = WalkSession(startedAt: started, steps: 5_000)
        walk.activity = .walking
        var run = WalkSession(startedAt: started, steps: 5_000)
        run.activity = .running

        // 0.04 kcal/step, the figure every walk already in Santé was written
        // with: it must not move, or the résumé would show a different number
        // for sessions nobody touched.
        #expect(walk.estimatedCalories == 200)
        // A run does not burn a walking figure. The phone writes no energy
        // *samples* (they'd double-count the daily total), so this estimate is
        // the only energy a phone-recorded run will ever carry.
        #expect(run.estimatedCalories > walk.estimatedCalories)
        // The literal 0.09 kcal/step produces, not the expression the code
        // under test uses: recomputing `5_000 * kcalPerStep` here would be
        // true for any value of the constant — the trap line 21 warns about.
        #expect(run.estimatedCalories == 450)
    }

    @Test("A session defaults to walking when no activity is given")
    func defaultsToWalking() {
        #expect(WalkSession(startedAt: .now).activity == .walking)
    }
}
