import Foundation

/// The streak-relevant preferences the phone pushes to the Watch so the watch
/// computes the *same* streak: the activity goal and which weekdays count
/// (rest days must be skipped, not break the streak). Sent via WatchConnectivity
/// application context; persisted on the watch so it survives relaunches.
struct WatchSyncPayload: Codable, Sendable {
    var minutesGoal: Int
    var stepsGoal: Int
    /// Active weekdays as `Calendar` numbers (1 = Sunday … 7 = Saturday) — the
    /// shape `StreakCalculator` consumes, so the watch needs no `Weekday` type.
    var activeWeekdays: [Int]
}

/// Watch-side persistence of the last payload received from the phone
/// (`UserDefaults.standard` — same process as the receiver and the views).
enum WatchSyncStore {
    private static let key = "watch.sync.payload"

    static func write(_ payload: WatchSyncPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func read() -> WatchSyncPayload? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchSyncPayload.self, from: data)
    }
}
