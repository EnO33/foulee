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
    // Hydration: whether the feature is on, and the goal / glass size so the
    // watch can show the same card.
    var hydrationEnabled: Bool
    var hydrationGoalML: Int
    var hydrationGlassML: Int

    init(
        streak: Int,
        minutesGoal: Int,
        stepsGoal: Int,
        hydrationEnabled: Bool = false,
        hydrationGoalML: Int = 2_000,
        hydrationGlassML: Int = 250
    ) {
        self.streak = streak
        self.minutesGoal = minutesGoal
        self.stepsGoal = stepsGoal
        self.hydrationEnabled = hydrationEnabled
        self.hydrationGoalML = hydrationGoalML
        self.hydrationGlassML = hydrationGlassML
    }

    // Tolerant decoding: payloads written before hydration shipped lack the
    // hydration keys — fall back to defaults instead of failing the whole
    // decode (which would briefly blank the streak after an update).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streak = try container.decode(Int.self, forKey: .streak)
        minutesGoal = try container.decode(Int.self, forKey: .minutesGoal)
        stepsGoal = try container.decode(Int.self, forKey: .stepsGoal)
        hydrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .hydrationEnabled) ?? false
        hydrationGoalML = try container.decodeIfPresent(Int.self, forKey: .hydrationGoalML) ?? 2_000
        hydrationGlassML = try container.decodeIfPresent(Int.self, forKey: .hydrationGlassML) ?? 250
    }
}

/// Watch-side persistence of the last payload received from the phone. Stored
/// in the shared app group so both the watch app (which writes it on receipt)
/// and the watch widget extension (a separate process) read the same value.
enum WatchSyncStore {
    private static let key = "watch.sync.payload"
    private static let suiteName = "group.com.eno33.foulee"

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // The `defaults` parameter is a test seam: production call sites rely on
    // the default (the app-group suite); tests inject an isolated suite.
    static func write(_ payload: WatchSyncPayload, to defaults: UserDefaults = Self.sharedDefaults) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }

    static func read(from defaults: UserDefaults = Self.sharedDefaults) -> WatchSyncPayload? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchSyncPayload.self, from: data)
    }
}
