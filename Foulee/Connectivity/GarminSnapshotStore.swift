import Foundation

/// Where the Connect IQ channel keeps its state between two BLE deliveries
/// (issue #189): the last accepted snapshot, the day's overlay floor, and why
/// the last snapshot was refused.
///
/// **Persisted, not in-memory only.** iOS relaunches the app in the background
/// on BLE activity and suspends or kills it again between wakes, and the watch
/// only pushes when its own metrics moved — so an in-memory overlay would be
/// gone on nearly every wake and the displayed counters would fall back to
/// HealthKit-only, i.e. visibly *drop*, until the watch happened to move again.
///
/// **`UserDefaults.standard`, not the app group.** No other process needs it:
/// the widgets read the merged result through `WidgetSnapshot`, never anything
/// here. Same boundary as `GarminDeviceStore` — the Connect IQ channel has no
/// business inside the shared container.
///
/// Two records, two different gates, on purpose:
///
/// - `read` returns the last accepted snapshot only while it is still *usable*
///   (same day, within `GarminSnapshotOverlay.freshnessHorizon`). It exists to
///   order the stream (`supersedes`), and an expired record must stop blocking
///   — that is also how a watch-side counter reset recovers on its own.
/// - `readFloor` returns the day's high-water contribution, gated on the local
///   day alone. It is what the counters actually display, and it deliberately
///   outlives the freshness horizon — see `GarminSnapshotOverlay.Floor`.
enum GarminSnapshotStore {
    private static let key = "garmin.connectiq.snapshot"
    private static let floorKey = "garmin.connectiq.overlayFloor"
    private static let outcomeKey = "garmin.connectiq.lastOutcome"

    static func write(_ snapshot: GarminDailySnapshot, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func read(
        now: Date = .now,
        from defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> GarminDailySnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(GarminDailySnapshot.self, from: data),
              GarminSnapshotOverlay.isUsable(snapshot, now: now, calendar: calendar)
        else { return nil }
        return snapshot
    }

    // MARK: - The day's floor

    /// Raise today's floor with a contribution that just passed the freshness
    /// gate. A floor stamped another day is replaced, never raised.
    static func raiseFloor(
        with contribution: GarminSnapshotOverlay.Contribution,
        now: Date = .now,
        to defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        let raised = GarminSnapshotOverlay.raised(
            storedFloor(from: defaults), with: contribution, now: now, calendar: calendar
        )
        guard let data = try? JSONEncoder().encode(raised) else { return }
        defaults.set(data, forKey: floorKey)
    }

    /// What the day's floor still contributes at `now` — nothing once local
    /// midnight has passed.
    static func readFloor(
        now: Date = .now,
        from defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> GarminSnapshotOverlay.Contribution? {
        GarminSnapshotOverlay.standing(storedFloor(from: defaults), now: now, calendar: calendar)
    }

    private static func storedFloor(from defaults: UserDefaults) -> GarminSnapshotOverlay.Floor? {
        guard let data = defaults.data(forKey: floorKey) else { return nil }
        return try? JSONDecoder().decode(GarminSnapshotOverlay.Floor.self, from: data)
    }

    // MARK: - Why the last snapshot was refused

    /// The verdict on the last snapshot the app decoded.
    ///
    /// This target logs nothing on purpose, and a total refusal is otherwise
    /// invisible: a watch clock more than `clockSkewTolerance` ahead rejects
    /// *every* snapshot, for good, with no signal anywhere. Keeping the last
    /// verdict gives that failure a place to be read from — by a test today,
    /// by a debug surface later — without a logger.
    static func recordOutcome(_ outcome: GarminSnapshotIngestion.Outcome, to defaults: UserDefaults = .standard) {
        defaults.set(outcome.rawValue, forKey: outcomeKey)
    }

    static func lastOutcome(from defaults: UserDefaults = .standard) -> GarminSnapshotIngestion.Outcome? {
        (defaults.string(forKey: outcomeKey)).flatMap(GarminSnapshotIngestion.Outcome.init(rawValue:))
    }
}
