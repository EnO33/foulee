import Foundation

/// What the phone sends the Foulée Monkey C app: the state the Apple Watch
/// already gets as `WatchSyncPayload`, as a Connect IQ message (ADR 0009, D5
/// and D6). The streak is computed on the phone, the single source of truth;
/// the watch only shows it.
///
/// A Connect IQ message is a dictionary of strings, numbers and booleans, not
/// JSON. Keys stay short: the BLE link runs at about 1 KB/s. Every send is the
/// complete state, so a watch that missed one is put right by the next.
nonisolated public enum GarminPhoneSync {
    /// The `t` of this message. The watch ignores any other.
    public static let messageType = "sync"

    /// Bumped when the shape changes: an older watch app then drops the
    /// message whole instead of half-reading it.
    public static let schemaVersion = 1

    public static func message(from payload: WatchSyncPayload) -> [String: Any] {
        [
            "t": messageType,
            "v": schemaVersion,
            "streak": payload.streak,
            "minutesGoal": payload.minutesGoal,
            "stepsGoal": payload.stepsGoal,
            "mode": payload.activityMode.rawValue,
            "water": payload.hydrationEnabled,
            "waterGoalML": payload.hydrationGoalML,
            "glassML": payload.hydrationGlassML,
        ]
    }
}
