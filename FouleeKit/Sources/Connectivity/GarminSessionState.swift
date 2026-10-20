import Foundation

/// A session in progress on the Garmin watch, as the Foulée Monkey C app
/// states it every 10 s and at each pause, resume and end (`session`, ADR 0009,
/// D7 and D6). Read into the `WatchSessionSnapshot` the Apple Watch's mirror
/// already draws: the same complete, dated state (ADR 0003, D2), so the mirror
/// screen and its rules (newest wins, the end closes it) serve both watches.
///
/// The wire format is a Connect IQ message dictionary, shared verbatim with
/// `FouleeConnectIQ/source/SessionMessage.mc`:
///
///     { "t": "session", "v", "sport", "sent", "elapsed", "distanceM",
///       "steps", "hr", "paused", "ended" }
///
/// `sent` is epoch seconds; `elapsed` the recorded time in seconds, pauses
/// excluded; `hr` 0 when there is none; `paused` and `ended` 0 or 1.
nonisolated public enum GarminSessionState {
    public static let messageType = "session"

    /// Latest schema version this build reads. A newer one is dropped whole.
    public static let schemaVersion = 1

    nonisolated private enum Key {
        static let type = "t"
        static let version = "v"
        static let sport = "sport"
        static let sent = "sent"
        static let elapsed = "elapsed"
        static let distance = "distanceM"
        static let steps = "steps"
        static let heartRate = "hr"
        static let paused = "paused"
        static let ended = "ended"
    }

    /// Tolerant decoder for a raw Connect IQ message, in the manner of
    /// `GarminSessionSummary.decode`:
    ///
    /// - another `t`, or a `v` this build doesn't know → rejected whole;
    /// - missing or non-positive `sent` → rejected (it dates the figures);
    /// - an unknown `sport` → walking;
    /// - missing or non-numeric metric → 0, negative → 0.
    ///
    /// The watch has no calories to state: they stay 0, and the screen says so.
    public static func decode(_ message: Any) -> WatchSessionSnapshot? {
        guard let fields = message as? [AnyHashable: Any],
              fields[Key.type] as? String == messageType,
              ConnectIQField.integer(fields[Key.version]) == schemaVersion,
              let sentAt = ConnectIQField.positiveDate(fields[Key.sent]) else { return nil }

        let elapsed = TimeInterval(ConnectIQField.nonNegative(fields[Key.elapsed]))
        let heartRate = ConnectIQField.nonNegative(fields[Key.heartRate])
        return WatchSessionSnapshot(
            sentAt: sentAt,
            // The start pushed back by every pause, as the Apple Watch states
            // it: the phone's clock then runs from it between two states.
            outingStartedAt: sentAt.addingTimeInterval(-elapsed),
            activity: ConnectIQField.activity(fields[Key.sport]),
            steps: ConnectIQField.nonNegative(fields[Key.steps]),
            distanceMeters: Double(ConnectIQField.nonNegative(fields[Key.distance])),
            activeCalories: 0,
            heartRate: heartRate > 0 ? heartRate : nil,
            isEnded: ConnectIQField.flag(fields[Key.ended]),
            isPaused: ConnectIQField.flag(fields[Key.paused])
        )
    }
}
