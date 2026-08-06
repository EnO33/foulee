import Foundation
import Testing
import WatchConnectivity
@testable import Foulee

@Suite("WatchSyncPayload")
struct WatchSyncPayloadTests {
    @Test("Round-trips through JSON")
    func roundTrip() throws {
        let payload = WatchSyncPayload(
            streak: 12,
            minutesGoal: 30,
            stepsGoal: 8_000,
            hydrationEnabled: true,
            hydrationGoalML: 1_500,
            hydrationGlassML: 200,
            activityMode: .running
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchSyncPayload.self, from: data)
        #expect(decoded.streak == 12)
        #expect(decoded.minutesGoal == 30)
        #expect(decoded.stepsGoal == 8_000)
        #expect(decoded.hydrationEnabled)
        #expect(decoded.hydrationGoalML == 1_500)
        #expect(decoded.hydrationGlassML == 200)
        // The watch has no settings screen: this field is the only way it can
        // know it should stamp sessions as runs (issue #223).
        #expect(decoded.activityMode == .running)
    }

    @Test("Pre-hydration payloads decode with hydration defaults")
    func tolerantDecoding() throws {
        let json = #"{"streak":5,"minutesGoal":20,"stepsGoal":6000}"#
        let decoded = try JSONDecoder().decode(WatchSyncPayload.self, from: Data(json.utf8))
        #expect(decoded.streak == 5)
        #expect(decoded.minutesGoal == 20)
        #expect(decoded.stepsGoal == 6_000)
        #expect(!decoded.hydrationEnabled)
        #expect(decoded.hydrationGoalML == 2_000)
        #expect(decoded.hydrationGlassML == 250)
        // Same tolerance for the activity mode: a payload the watch persisted
        // before this shipped must keep decoding, and an install that never
        // chose is a walking install.
        #expect(decoded.activityMode == .walking)
    }
}

@Suite("PhoneWatchSync")
struct PhoneWatchSyncTests {
    @Test("Pushes only once activated with the watch app installed")
    func canPushGating() {
        #expect(PhoneWatchSync.canPush(activationState: .activated, isWatchAppInstalled: true))
        #expect(!PhoneWatchSync.canPush(activationState: .activated, isWatchAppInstalled: false))
        #expect(!PhoneWatchSync.canPush(activationState: .notActivated, isWatchAppInstalled: true))
        #expect(!PhoneWatchSync.canPush(activationState: .inactive, isWatchAppInstalled: true))
    }
}
