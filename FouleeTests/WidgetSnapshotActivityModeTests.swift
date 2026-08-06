import Foundation
import Testing
@testable import Foulee

/// The activity mode travelling in the app-group snapshot (issue #222).
///
/// Split from `WidgetSnapshotTests` for length, and because it pins a
/// different property: that suite is about numbers the widget may not get
/// wrong, this one about a field whose only job is to pick a glyph — and
/// which therefore must never be able to take a snapshot down with it.
@Suite("WidgetSnapshot activity mode")
struct WidgetSnapshotActivityModeTests {
    private let today = Calendar.current.startOfDay(for: .now)

    private func snapshot(day: Date?) -> WidgetSnapshot {
        WidgetSnapshot(
            steps: 4_200, stepsGoal: 6_000, minutes: 25, minutesGoal: 20,
            distanceKm: 3.1, calories: 180, streak: 7,
            waterML: 750, waterGoalML: 1_500, hydrationEnabled: true,
            day: day
        )
    }

    @Test("A snapshot written before the mode travelled reads as walking")
    func tolerantDecodingWithoutTheActivityMode() throws {
        // Every install that has not updated yet: no `activityMode` key at
        // all. Walking is what those widgets were already drawing and what
        // `UserPreferences` defaults to, so the glyph must not move under
        // anyone on the update itself.
        let json = """
        {"steps":1200,"stepsGoal":6000,"minutes":8,"minutesGoal":20,\
        "distanceKm":0.9,"calories":55,"streak":3}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(decoded.activityMode == .walking)
    }

    @Test("A mode this build doesn't know falls back instead of failing the decode")
    func unknownActivityModeDoesNotBlankTheWidget() throws {
        // The downgrade case: a later build adds a fourth mode, the user rolls
        // back, and this decoder meets a raw value it has no case for. Decoding
        // the field as `ActivityMode` would throw and take the *whole* snapshot
        // with it — every widget blank, streak included — over a field that
        // only picks a glyph.
        let json = """
        {"steps":1200,"stepsGoal":6000,"minutes":8,"minutesGoal":20,\
        "distanceKm":0.9,"calories":55,"streak":3,"activityMode":"cycling"}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(decoded.activityMode == .walking)
        #expect(decoded.streak == 3)
    }

    @Test("The mode round-trips, and survives midnight like the other settings")
    func activityModeRoundTripsAndSurvivesMidnight() throws {
        var running = snapshot(day: today)
        running.activityMode = .running
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(running))
        #expect(decoded.activityMode == .running)

        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        var stale = snapshot(day: yesterday)
        stale.activityMode = .running
        // A preference, not a daily counter: zeroing the day must not reset it
        // to walking and hand a runner a walking figure every morning.
        #expect(stale.zeroedIfStale(today: today).activityMode == .running)
    }
}
