import Foundation
import Testing
@testable import FouleeKit

/// The keys below are the contract with `FouleeConnectIQ/source/PhoneSync.mc`:
/// renaming one on either side silently blanks a field on the watch.
@Suite("Garmin phone sync message")
struct GarminPhoneSyncTests {
    @Test("The message carries the whole synced state, typed and versioned")
    func fullState() {
        let payload = WatchSyncPayload(
            streak: 12,
            minutesGoal: 30,
            stepsGoal: 8_000,
            hydrationEnabled: true,
            hydrationGoalML: 2_000,
            hydrationGlassML: 250,
            activityMode: .both
        )
        let message = GarminPhoneSync.message(from: payload)

        #expect(message["t"] as? String == "sync")
        #expect(message["v"] as? Int == 1)
        #expect(message["streak"] as? Int == 12)
        #expect(message["minutesGoal"] as? Int == 30)
        #expect(message["stepsGoal"] as? Int == 8_000)
        #expect(message["mode"] as? String == "both")
        #expect(message["water"] as? Bool == true)
        #expect(message["waterGoalML"] as? Int == 2_000)
        #expect(message["glassML"] as? Int == 250)
        #expect(message.count == 9)
    }

    @Test("Every activity mode travels as the raw value the watch decodes")
    func activityModes() {
        for mode in ActivityMode.allCases {
            let payload = WatchSyncPayload(streak: 0, minutesGoal: 0, stepsGoal: 0, activityMode: mode)
            #expect(GarminPhoneSync.message(from: payload)["mode"] as? String == mode.rawValue)
        }
    }
}
