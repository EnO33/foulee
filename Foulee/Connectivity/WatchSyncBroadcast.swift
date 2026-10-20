import FouleeKit

/// The phone-computed state every watch shows: the streak, the goals, the
/// activity mode and the hydration settings. The Apple Watch gets it over
/// WatchConnectivity, a Garmin watch over Connect IQ (ADR 0009, D5). One entry
/// point, so the two watches can never be told different things.
nonisolated enum WatchSyncBroadcast {
    static func send(_ payload: WatchSyncPayload) {
        PhoneWatchSync.shared.send(payload)
        GarminConnectIQBridge.shared.sendSync(payload)
    }
}
