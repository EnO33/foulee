import Foundation
import Testing
@testable import Foulee

/// The phone's session as the wrist is told of it (issue #342).
@Suite("Phone session snapshot")
struct PhoneSessionSnapshotTests {
    private let sent = Date(timeIntervalSince1970: 1_754_000_000)

    private func snapshot(_ phase: PhoneSessionSnapshot.Phase) -> PhoneSessionSnapshot {
        PhoneSessionSnapshot(
            sentAt: sent,
            activity: .running,
            phase: phase,
            elapsed: 600,
            steps: 1_800,
            distanceMeters: 1_650,
            activeCalories: 150,
            route: [MirroredRoutePortion(
                activity: .running,
                coordinates: [Coordinate(latitude: 44.83, longitude: -0.57), Coordinate(latitude: 44.84, longitude: -0.58)]
            )]
        )
    }

    @Test("A snapshot survives the round trip whole")
    func roundTrip() throws {
        let original = snapshot(.paused)
        let decoded = try JSONDecoder().decode(PhoneSessionSnapshot.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    /// The two apps update separately: what this build cannot name still shows.
    @Test("An unknown sport or phase degrades instead of failing")
    func tolerantDecoding() throws {
        let json = #"{"sentAt": 0, "activity": "natation", "phase": "sieste", "steps": 12}"#
        let decoded = try JSONDecoder().decode(PhoneSessionSnapshot.self, from: Data(json.utf8))
        #expect(decoded.activity == .walking)
        #expect(decoded.phase == .active)
        #expect(decoded.steps == 12)
        #expect(decoded.route.isEmpty)
    }

    /// The wrist runs the clock on its own from this date between deliveries.
    @Test("An active session carries its clock's zero; a paused one freezes it")
    func timerBasis() {
        #expect(snapshot(.active).timerBasis == sent.addingTimeInterval(-600))
        #expect(snapshot(.paused).timerBasis == nil)
    }

    // MARK: - The application context

    /// `updateApplicationContext` replaces the whole dictionary: the session
    /// must travel with the synced prefs, never instead of them.
    @Test("The context carries the prefs and the session together")
    func theContextCarriesBoth() throws {
        let context = PhoneWatchSync.Context(
            payload: WatchSyncPayload(streak: 12, minutesGoal: 30, stepsGoal: 8_000),
            session: snapshot(.active)
        ).dictionary

        #expect(context["payload"] is Data)
        let data = try #require(context[PhoneSessionKey.snapshot] as? Data)
        #expect(try JSONDecoder().decode(PhoneSessionSnapshot.self, from: data) == snapshot(.active))
    }

    /// An absent key is how the wrist learns there is no session any more.
    @Test("No session leaves its key out")
    func noSessionNoKey() {
        let context = PhoneWatchSync.Context(
            payload: WatchSyncPayload(streak: 12, minutesGoal: 30, stepsGoal: 8_000)
        ).dictionary
        #expect(context[PhoneSessionKey.snapshot] == nil)
        #expect(context["payload"] != nil)
    }
}
