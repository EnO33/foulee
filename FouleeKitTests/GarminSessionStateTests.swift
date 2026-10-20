import Foundation
import Testing
@testable import FouleeKit

/// The keys below are the contract with
/// `FouleeConnectIQ/source/SessionMessage.mc`.
@Suite("Garmin session state")
struct GarminSessionStateTests {
    private static let sent = Date(timeIntervalSince1970: 1_760_962_200)

    private static func message(_ overrides: [String: Any] = [:]) -> [String: Any] {
        [
            "t": "session",
            "v": 1,
            "sport": "running",
            "sent": 1_760_962_200,
            "elapsed": 540,
            "distanceM": 900,
            "steps": 1_200,
            "hr": 112,
            "paused": 0,
            "ended": 0,
        ].merging(overrides) { _, new in new }
    }

    @Test("The whole state is read, the start set back by the time recorded")
    func fullMessage() throws {
        let state = try #require(GarminSessionState.decode(Self.message()))
        #expect(state.sentAt == Self.sent)
        #expect(state.outingStartedAt == Self.sent.addingTimeInterval(-540))
        #expect(state.elapsed(at: Self.sent) == 540)
        #expect(state.activity == .running)
        #expect(state.distanceMeters == 900)
        #expect(state.steps == 1_200)
        #expect(state.heartRate == 112)
        #expect(state.activeCalories == 0)
        #expect(!state.isPaused && !state.isEnded)
        #expect(state.route.isEmpty)
    }

    @Test("Paused and ended are read from their 0-or-1 flags")
    func flags() throws {
        let paused = try #require(GarminSessionState.decode(Self.message(["paused": 1])))
        #expect(paused.isPaused && !paused.isEnded)
        let ended = try #require(GarminSessionState.decode(Self.message(["paused": 1, "ended": 1])))
        #expect(ended.isEnded)
    }

    @Test("No heart rate is none, not zero beats")
    func noHeartRate() throws {
        #expect(try #require(GarminSessionState.decode(Self.message(["hr": 0]))).heartRate == nil)
        #expect(try #require(GarminSessionState.decode(Self.message(["hr": "112"]))).heartRate == nil)
    }

    @Test("Another type, another version or no date is refused whole")
    func refused() {
        #expect(GarminSessionState.decode(Self.message(["t": "summary"])) == nil)
        #expect(GarminSessionState.decode(Self.message(["v": 2])) == nil)
        #expect(GarminSessionState.decode(Self.message(["sent": 0])) == nil)
        #expect(GarminSessionState.decode("session") == nil)
    }

    @Test("An unknown sport is a walk, a bad figure is zero")
    func tolerant() throws {
        let state = try #require(GarminSessionState.decode(Self.message([
            "sport": "swimming", "steps": -3, "distanceM": "far",
        ])))
        #expect(state.activity == .walking)
        #expect(state.steps == 0)
        #expect(state.distanceMeters == 0)
    }
}
