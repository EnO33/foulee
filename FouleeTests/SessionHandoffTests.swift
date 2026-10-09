import Foundation
import Testing
@testable import Foulee

/// What the phone hands the wrist when it carries a walk on (issue #335), and
/// the application context it rides in.
@Suite("Session handoff")
struct SessionHandoffTests {
    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    private var handoff: SessionHandoff {
        SessionHandoff(
            outingID: UUID(uuidString: "6B0E3A58-2F1C-4C1E-9A6E-3E5D1F0B7C21")!,
            phoneLeg: SessionHandoff.Leg(
                activity: .running,
                start: base.addingTimeInterval(-900),
                end: base,
                steps: 2_400,
                distanceMeters: 2_100,
                activeCalories: 216
            )
        )
    }

    @Test("A handoff survives the round trip whole")
    func roundTrip() throws {
        let decoded = try JSONDecoder().decode(SessionHandoff.self, from: JSONEncoder().encode(handoff))
        #expect(decoded == handoff)
    }

    /// The two apps update separately: a sport this build cannot name is still
    /// a walk to carry on, not a handoff thrown away.
    @Test("An unknown sport is carried on as a walk")
    func anUnknownSportDegrades() throws {
        let json = """
        {"outingID": "6B0E3A58-2F1C-4C1E-9A6E-3E5D1F0B7C21",
         "phoneLeg": {"activity": "natation", "start": 0, "end": 60}}
        """
        let decoded = try JSONDecoder().decode(SessionHandoff.self, from: Data(json.utf8))
        #expect(decoded.phoneLeg.activity == .walking)
        #expect(decoded.phoneLeg.steps == 0)
    }

    @Test("The wrist carries on at leg 1 of the same outing, from where the phone stopped")
    func theWristCarriesOn() {
        #expect(handoff.continuingLeg == OutingLeg(outingID: handoff.outingID, index: 1))
        #expect(handoff.handedOverAt == base)
    }

    @Test("A handoff nobody collected goes stale")
    func freshness() {
        #expect(handoff.isFresh(at: base.addingTimeInterval(SessionHandoff.freshness)))
        #expect(!handoff.isFresh(at: base.addingTimeInterval(SessionHandoff.freshness + 1)))
    }

    // MARK: - The application context

    /// `updateApplicationContext` replaces the whole dictionary: the walk's
    /// state must travel with the synced prefs, never instead of them.
    @Test("The context carries the prefs, the walk and the handoff together")
    func theContextCarriesEverything() throws {
        let context = PhoneWatchSync.Context(
            payload: WatchSyncPayload(streak: 12, minutesGoal: 30, stepsGoal: 8_000),
            phoneSession: PhoneSessionStatus(startedAt: base),
            handoff: handoff
        ).dictionary

        #expect(context["payload"] is Data)
        let session = try #require(context[SessionHandoffKey.phoneSession] as? Data)
        #expect(try JSONDecoder().decode(PhoneSessionStatus.self, from: session).startedAt == base)
        let sent = try #require(context[SessionHandoffKey.handoff] as? Data)
        #expect(try JSONDecoder().decode(SessionHandoff.self, from: sent) == handoff)
    }

    /// An absent key is how the wrist learns the walk is over.
    @Test("A walk that is over leaves its key out")
    func noWalkNoKey() {
        let context = PhoneWatchSync.Context(
            payload: WatchSyncPayload(streak: 12, minutesGoal: 30, stepsGoal: 8_000)
        ).dictionary
        #expect(context[SessionHandoffKey.phoneSession] == nil)
        #expect(context[SessionHandoffKey.handoff] == nil)
        #expect(context["payload"] != nil)
    }
}
