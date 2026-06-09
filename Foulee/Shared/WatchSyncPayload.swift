import Foundation

/// What the phone pushes to the Watch. The streak is computed on the phone —
/// the single source of truth — because the watch's local HealthKit only keeps
/// a few days of history, so recomputing there undercounts long streaks. The
/// goals ride along for the watch UI. Sent via WatchConnectivity application
/// context; persisted on the watch so it survives relaunches.
struct WatchSyncPayload: Codable, Sendable {
    var streak: Int
    var minutesGoal: Int
    var stepsGoal: Int
}

/// Watch-side persistence of the last payload received from the phone. Stored
/// in the shared app group so both the watch app (which writes it on receipt)
/// and the watch widget extension (a separate process) read the same value.
enum WatchSyncStore {
    private static let key = "watch.sync.payload"
    private static let suiteName = "group.com.eno33.foulee"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func write(_ payload: WatchSyncPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> WatchSyncPayload? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchSyncPayload.self, from: data)
    }
}
