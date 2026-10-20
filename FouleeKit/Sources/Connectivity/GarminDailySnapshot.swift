import Foundation

/// One daily activity snapshot pushed by the Foulée Monkey C app over the
/// Connect IQ BLE channel (issues #187 / #188).
///
/// The wire format is a Connect IQ message dictionary — `NSString` keys,
/// `NSNumber` values — not JSON, so it gets its own hand-written decoder
/// rather than `Codable`. The schema is shared verbatim with the watch side:
///
///     { "t", "v", "steps", "distanceCm", "activeMinutes",
///       "activeMinutesVigorous", "calories", "ts", "day", "gen" }
///
/// - `t`  — message type, `"snapshot"` (ADR 0009, D6). Absent from v1.
/// - `v`  — schema version, 1 or 2. A payload from a newer watch app is
///          dropped whole rather than half-read.
/// - `ts` — snapshot instant, epoch seconds UTC (`Time.now().value()`).
/// - `day`— v2: start of the watch's own local day, epoch seconds
///          (`Time.today().value()`). The watch's counters reset at *its*
///          midnight, which is not the phone's when the two sit in different
///          time zones (#473).
/// - `gen`— watch-side counter, incremented on every snapshot the watch builds.
///          BLE can redeliver and reorder, so this is what orders the stream.
///
/// Units follow `Toybox.ActivityMonitor.Info` exactly: distance in centimetres,
/// minutes in whole minutes, calories in kilocalories. No conversion happens
/// here. How these values are merged with what Garmin Connect already wrote
/// into Santé — and why they are never written there themselves — is
/// `GarminSnapshotOverlay` (#189).
/// `Codable` so the overlay survives a relaunch — iOS wakes the app in the
/// background on BLE activity and kills it again between wakes
/// (`GarminSnapshotStore`, #189).
nonisolated public struct GarminDailySnapshot: Codable, Equatable, Sendable {
    /// Latest schema version this build reads; every version from 1 up to it
    /// is accepted, since watches update on their own schedule. Bumping it
    /// means the watch app changed shape: older phone builds then reject the
    /// payload instead of guessing.
    public static let schemaVersion = 2

    /// The only `t` a snapshot may carry. Other message types (ADR 0009, D6)
    /// are not snapshots and are refused here.
    public static let messageType = "snapshot"

    public var steps: Int
    public var distanceCm: Int
    /// Total active minutes for the day — Garmin's `activeMinutesDay.total`,
    /// the native equivalent of `appleExerciseTime` (ADR 0001).
    public var activeMinutes: Int
    /// The vigorous share of `activeMinutes`, kept apart because Garmin counts
    /// vigorous minutes double in its own totals — `GarminSnapshotOverlay`
    /// subtracts it back out to get wall-clock minutes comparable to
    /// `appleExerciseTime`.
    public var activeMinutesVigorous: Int
    public var calories: Int
    public var timestamp: Date
    /// Start of the watch's local day, from a v2 payload; nil from v1, whose
    /// day can only be read off `timestamp` in the phone's time zone (#473).
    public var watchDayStart: Date?
    public var generation: Int

    public init(
        steps: Int,
        distanceCm: Int,
        activeMinutes: Int,
        activeMinutesVigorous: Int,
        calories: Int,
        timestamp: Date,
        watchDayStart: Date? = nil,
        generation: Int
    ) {
        self.steps = steps
        self.distanceCm = distanceCm
        self.activeMinutes = activeMinutes
        self.activeMinutesVigorous = activeMinutesVigorous
        self.calories = calories
        self.timestamp = timestamp
        self.watchDayStart = watchDayStart
        self.generation = generation
    }
}

nonisolated public extension GarminDailySnapshot {
    nonisolated private enum Key {
        static let type = "t"
        static let version = "v"
        static let steps = "steps"
        static let distanceCm = "distanceCm"
        static let activeMinutes = "activeMinutes"
        static let activeMinutesVigorous = "activeMinutesVigorous"
        static let calories = "calories"
        static let timestamp = "ts"
        static let dayStart = "day"
        static let generation = "gen"
    }

    /// Tolerant decoder for a raw Connect IQ message.
    ///
    /// The message crosses a BLE link from a device the app doesn't control,
    /// so this never traps and never throws — anything it can't make sense of
    /// becomes `nil` and the caller drops the snapshot:
    ///
    /// - unknown or missing `v` → rejected whole (forward compatibility);
    /// - a `t` other than `"snapshot"` → rejected (another message type);
    /// - v2 `day` missing or not a positive number → no watch day, and the
    ///   phone's time zone decides, as for v1;
    /// - missing or non-numeric `ts`/`gen` → rejected (they order the stream);
    /// - missing or non-numeric metric → 0 (a watch build that predates a
    ///   metric shouldn't cost us the whole snapshot);
    /// - negative metric → clamped to 0;
    /// - unknown keys → ignored, so the watch side can add fields freely.
    static func decode(_ message: Any) -> GarminDailySnapshot? {
        // `[AnyHashable: Any]` rather than `[String: Any]`: Monkey C allows
        // non-string keys, and a single stray one would otherwise fail the
        // cast for the whole dictionary.
        guard let fields = message as? [AnyHashable: Any],
              isSnapshotType(fields[Key.type]),
              let version = ConnectIQField.integer(fields[Key.version]),
              (1...schemaVersion).contains(version),
              let timestamp = ConnectIQField.positiveDate(fields[Key.timestamp]),
              let generation = ConnectIQField.integer(fields[Key.generation]),
              generation >= 0 else { return nil }

        return GarminDailySnapshot(
            steps: ConnectIQField.nonNegative(fields[Key.steps]),
            distanceCm: ConnectIQField.nonNegative(fields[Key.distanceCm]),
            activeMinutes: ConnectIQField.nonNegative(fields[Key.activeMinutes]),
            activeMinutesVigorous: ConnectIQField.nonNegative(fields[Key.activeMinutesVigorous]),
            calories: ConnectIQField.nonNegative(fields[Key.calories]),
            timestamp: timestamp,
            watchDayStart: version >= 2 ? ConnectIQField.positiveDate(fields[Key.dayStart]) : nil,
            generation: generation
        )
    }

    /// Whether `incoming` should replace `lastAccepted`.
    ///
    /// Pure, so the ordering rule is unit-testable without any BLE hardware.
    /// A strictly newer generation always wins; within one generation only a
    /// strictly newer timestamp does, which drops the duplicate deliveries BLE
    /// is prone to. A *lower* generation is always stale — a watch-side counter
    /// reset (app reinstall) recovers on its own because `GarminSnapshotIngestion`
    /// compares against the *fresh* stored snapshot, which expires (#189).
    static func supersedes(_ incoming: GarminDailySnapshot, lastAccepted: GarminDailySnapshot?) -> Bool {
        guard let last = lastAccepted else { return true }
        if incoming.generation != last.generation { return incoming.generation > last.generation }
        return incoming.timestamp > last.timestamp
    }

    /// No `t` at all is a v1 snapshot, which predates message types.
    private static func isSnapshotType(_ value: Any?) -> Bool {
        guard let value else { return true }
        return value as? String == messageType
    }
}
