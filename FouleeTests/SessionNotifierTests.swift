import Dependencies
import FouleeKit
import Foundation
import Testing
@testable import Foulee

/// The notification of an outing that just landed (issue #529).
@Suite("Session notifier")
struct SessionNotifierTests {
    private static let start = Date(timeIntervalSince1970: 1_792_828_800)

    private func cleanDefaults() -> UserDefaults {
        let suiteName = "session-notifier-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private var walk: WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            startedAt: Self.start,
            endedAt: Self.start.addingTimeInterval(2_880),
            durationSeconds: 2_880,
            distanceKm: 5.2,
            activeCalories: 0,
            sourceName: "Garmin Connect",
            activity: .walking
        )
    }

    /// Runs `outingsChanged` once, `minutesAfterEnd` after the walk, and
    /// returns what reached iOS.
    private func run(
        _ defaults: UserDefaults,
        workouts: [WorkoutSummary],
        minutesAfterEnd: Double = 1
    ) async -> [SessionNotice] {
        let scheduled = LockedRef<[SessionNotice]>([])
        await withDependencies {
            $0.healthKit.recentWorkouts = { _ in workouts }
            $0.notifications.scheduleSessionNotice = { notice in scheduled.set(scheduled.value + [notice]) }
        } operation: {
            let now = Self.start.addingTimeInterval(2_880 + minutesAfterEnd * 60)
            await SessionNotifier().outingsChanged(now: now, defaults: defaults)
        }
        return scheduled.value
    }

    @Test("An outing that landed is announced, once its notification has gone")
    func announcedOnce() async {
        let defaults = cleanDefaults()
        SessionNotifier.prepare(now: Self.start, defaults: defaults)
        let walk = walk
        let first = await run(defaults, workouts: [walk])
        #expect(first.map(\.title) == ["Marche enregistrée"])
        #expect(first.map(\.body) == ["5,2 km en 48 min. Le détail t'attend."])
        #expect(await run(defaults, workouts: [walk], minutesAfterEnd: 5).isEmpty)
    }

    @Test("An outing recorded on this iPhone is not announced")
    func recordedHere() async {
        let defaults = cleanDefaults()
        SessionNotifier.prepare(now: Self.start, defaults: defaults)
        let walk = walk
        SessionNotifier.recordedHere(from: walk.startedAt, to: walk.endedAt, defaults: defaults)
        #expect(await run(defaults, workouts: [walk]).isEmpty)
    }

    @Test("Nothing that ended before the first launch is announced")
    func beforeFirstLaunch() async {
        let defaults = cleanDefaults()
        SessionNotifier.prepare(now: Self.start.addingTimeInterval(3_600), defaults: defaults)
        #expect(await run(defaults, workouts: [walk], minutesAfterEnd: 20).isEmpty)
    }

    /// Turned back on, nothing that landed while off is announced.
    @Test("Turned off, nothing is sent, and the register still follows")
    func turnedOff() async {
        let defaults = cleanDefaults()
        SessionNotifier.prepare(now: Self.start, defaults: defaults)
        let preferences = UserPreferences(defaults: defaults)
        #expect(preferences.sessionNotificationsEnabled)
        preferences.sessionNotificationsEnabled = false
        #expect(SessionNotifier.isEnabled(defaults) == false)
        let walk = walk
        #expect(await run(defaults, workouts: [walk]).isEmpty)
        preferences.sessionNotificationsEnabled = true
        #expect(await run(defaults, workouts: [walk], minutesAfterEnd: 10).isEmpty)
    }
}
