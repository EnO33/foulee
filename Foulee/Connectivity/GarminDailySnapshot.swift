import Foundation

/// One daily activity snapshot pushed by the Foulée Monkey C app over the
/// Connect IQ BLE channel (issues #187 / #188).
///
/// The wire format is a Connect IQ message dictionary — `NSString` keys,
/// `NSNumber` values — not JSON, so it gets its own hand-written decoder
/// rather than `Codable`. The schema is frozen and shared verbatim with the
/// watch side:
///
///     { "v", "steps", "distanceCm", "activeMinutes",
///       "activeMinutesVigorous", "calories", "ts", "gen" }
///
/// - `v`  — schema version. A payload from a newer watch app is dropped whole
///          rather than half-read.
/// - `ts` — snapshot instant, epoch seconds UTC (`Time.now().value()`).
/// - `gen`— watch-side counter, incremented on every snapshot the watch builds.
///          BLE can redeliver and reorder, so this is what orders the stream.
///
/// Units follow `Toybox.ActivityMonitor.Info` exactly: distance in centimetres,
/// minutes in whole minutes, calories in kilocalories. No conversion happens
/// here — decoding this struct is the end of this issue's scope; merging it
/// into HealthKit or the widget snapshot is #189.
struct GarminDailySnapshot: Equatable, Sendable {
    /// Frozen schema version. Bumping it means the watch app changed shape;
    /// old phone builds must then reject the payload instead of guessing.
    static let schemaVersion = 1

    var steps: Int
    var distanceCm: Int
    /// Total active minutes for the day — Garmin's `activeMinutesDay.total`,
    /// the native equivalent of `appleExerciseTime` (ADR 0001).
    var activeMinutes: Int
    /// The vigorous share of `activeMinutes`, kept apart because Garmin counts
    /// vigorous minutes double in its own totals. Interpreting that is #189.
    var activeMinutesVigorous: Int
    var calories: Int
    var timestamp: Date
    var generation: Int
}

extension GarminDailySnapshot {
    private enum Key {
        static let version = "v"
        static let steps = "steps"
        static let distanceCm = "distanceCm"
        static let activeMinutes = "activeMinutes"
        static let activeMinutesVigorous = "activeMinutesVigorous"
        static let calories = "calories"
        static let timestamp = "ts"
        static let generation = "gen"
    }

    /// Tolerant decoder for a raw Connect IQ message.
    ///
    /// The message crosses a BLE link from a device the app doesn't control,
    /// so this never traps and never throws — anything it can't make sense of
    /// becomes `nil` and the caller drops the snapshot:
    ///
    /// - unknown or missing `v` → rejected whole (forward compatibility);
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
              let version = integer(fields[Key.version]),
              version == schemaVersion,
              let seconds = finiteDouble(fields[Key.timestamp]),
              seconds > 0,
              let generation = integer(fields[Key.generation]),
              generation >= 0 else { return nil }

        return GarminDailySnapshot(
            steps: nonNegative(fields[Key.steps]),
            distanceCm: nonNegative(fields[Key.distanceCm]),
            activeMinutes: nonNegative(fields[Key.activeMinutes]),
            activeMinutesVigorous: nonNegative(fields[Key.activeMinutesVigorous]),
            calories: nonNegative(fields[Key.calories]),
            timestamp: Date(timeIntervalSince1970: seconds),
            generation: generation
        )
    }

    /// Whether `incoming` should replace `lastAccepted`.
    ///
    /// Pure, so the ordering rule is unit-testable without any BLE hardware.
    /// A strictly newer generation always wins; within one generation only a
    /// strictly newer timestamp does, which drops the duplicate deliveries BLE
    /// is prone to. A *lower* generation is always stale — if the watch app's
    /// counter ever resets (reinstall), the pairing has to be redone; #189
    /// owns that recovery.
    static func supersedes(_ incoming: GarminDailySnapshot, lastAccepted: GarminDailySnapshot?) -> Bool {
        guard let last = lastAccepted else { return true }
        if incoming.generation != last.generation { return incoming.generation > last.generation }
        return incoming.timestamp > last.timestamp
    }

    /// `NSNumber`-only on purpose: a numeric-looking `NSString` is a watch-side
    /// bug, and silently coercing it would hide it.
    private static func finiteDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let double = finiteDouble(value) else { return nil }
        // Saturate instead of trapping: `Int(_: Double)` crashes out of range,
        // and a corrupt payload must never take the app down.
        if double >= Double(Int.max) { return Int.max }
        if double <= Double(Int.min) { return Int.min }
        return Int(double.rounded())
    }

    private static func nonNegative(_ value: Any?) -> Int {
        max(0, integer(value) ?? 0)
    }
}
