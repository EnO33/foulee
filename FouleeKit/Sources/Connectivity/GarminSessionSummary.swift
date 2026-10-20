import Foundation

/// A session saved on the Garmin watch, as the Foulée Monkey C app sends it
/// at the end (`summary`, ADR 0009, D2 and D6). The watch saved it into Garmin
/// Connect, which writes it to Santé later, sometimes much later: until then
/// this is the only trace of the outing on the phone (`GarminPendingOutings`).
///
/// The wire format is a Connect IQ message dictionary, shared verbatim with
/// `FouleeConnectIQ/source/SessionMessage.mc`:
///
///     { "t": "summary", "v", "sport", "start", "end", "duration",
///       "distanceM", "steps" }
///
/// `start` and `end` are epoch seconds; `duration` is the recorded time in
/// seconds, pauses excluded, so it can be shorter than `end - start`.
nonisolated public struct GarminSessionSummary: Codable, Equatable, Sendable {
    public static let messageType = "summary"

    /// Latest schema version this build reads. A newer one is dropped whole.
    public static let schemaVersion = 1

    public var activity: SessionActivity
    /// Identifies the session: the watch records one at a time, so two
    /// deliveries with the same start are the same outing.
    public var startedAt: Date
    public var endedAt: Date
    public var durationSeconds: TimeInterval
    public var distanceMeters: Int
    public var steps: Int

    public init(
        activity: SessionActivity,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: TimeInterval,
        distanceMeters: Int,
        steps: Int
    ) {
        self.activity = activity
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.steps = steps
    }
}

nonisolated public extension GarminSessionSummary {
    nonisolated private enum Key {
        static let type = "t"
        static let version = "v"
        static let sport = "sport"
        static let start = "start"
        static let end = "end"
        static let duration = "duration"
        static let distance = "distanceM"
        static let steps = "steps"
    }

    /// Tolerant decoder for a raw Connect IQ message, in the manner of
    /// `GarminDailySnapshot.decode`:
    ///
    /// - another `t`, or a `v` this build doesn't know → rejected whole;
    /// - missing or non-positive `start`, or an `end` before it → rejected
    ///   (they place the outing on the clock);
    /// - an unknown `sport` → walking, the phone's own default;
    /// - missing or non-numeric metric → 0, negative → 0; a `duration` past
    ///   the wall clock is cut to it.
    static func decode(_ message: Any) -> GarminSessionSummary? {
        guard let fields = message as? [AnyHashable: Any],
              fields[Key.type] as? String == messageType,
              ConnectIQField.integer(fields[Key.version]) == schemaVersion,
              let start = ConnectIQField.positiveDate(fields[Key.start]),
              let end = ConnectIQField.positiveDate(fields[Key.end]),
              end >= start else { return nil }

        let duration = TimeInterval(ConnectIQField.nonNegative(fields[Key.duration]))
        return GarminSessionSummary(
            activity: (fields[Key.sport] as? String).flatMap(SessionActivity.init(rawValue:)) ?? .walking,
            startedAt: start,
            endedAt: end,
            durationSeconds: min(duration, end.timeIntervalSince(start)),
            distanceMeters: ConnectIQField.nonNegative(fields[Key.distance]),
            steps: ConnectIQField.nonNegative(fields[Key.steps])
        )
    }

    /// The clock the outing covers, as the minute count reads a workout.
    var interval: ActiveMinutes.WorkoutInterval {
        ActiveMinutes.WorkoutInterval(start: startedAt, duration: durationSeconds)
    }
}
