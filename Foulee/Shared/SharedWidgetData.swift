import Foundation

/// Today's progress, shared with the iOS widgets through the app group.
///
/// Widgets can't read HealthKit while the phone is locked (the store is
/// encrypted), so a widget that queries HealthKit directly shows 0 on the Lock
/// Screen. Instead the app — which already has the data — writes this snapshot
/// whenever it refreshes, and the widgets read it. The app-group container is
/// readable from the widget process and stays available after the first unlock,
/// so the Lock Screen keeps showing the last known values.
struct WidgetSnapshot: Codable, Sendable {
    var steps: Int
    var stepsGoal: Int
    var minutes: Int
    var minutesGoal: Int
    var distanceKm: Double
    var calories: Int
    var streak: Int
    // Hydration (added after 1.18 — tolerant decoding below keeps snapshots
    // written by older builds readable, so widgets never blank on update).
    var waterML: Int
    var waterGoalML: Int
    var hydrationEnabled: Bool
    /// Glass size preference mirrored here because the widget process can't
    /// read `UserDefaults.standard` — see `WaterGlass`.
    var hydrationGlassML: Int
    /// Local start-of-day when the snapshot was written (stamped by
    /// `SharedStore.write`). nil on snapshots from older builds — treated as
    /// stale, so readers zero the counters rather than show old totals.
    var day: Date?
    // How much of the counters above the widget process cannot re-measure —
    // the part the app lifted over raw HealthKit before writing them here, and
    // the floor the widget's own live read may not drop below (issue #214).
    //
    // Two overlays feed it, and neither is visible from the widget target: the
    // Connect IQ contribution (#189), which lives in the app's own
    // `UserDefaults.standard` and only ever arrives over BLE, and the
    // post-walk `PendingWalk` target (#158, #203), which lives in `TodayStore`'s
    // memory and covers the minute HealthKit takes to flush a finished walk.
    // Steps and distance take the max of both; minutes only ever see the watch,
    // since the walk overlay deliberately never fakes exercise minutes.
    //
    // Primitive numbers on purpose — the widget must know the three values it
    // may not drop, not either overlay's persistence format. Always ≤ the
    // counters they sit under: a floor above the total it accompanies would let
    // the widget rebuild a day the app itself refuses to show (#201).
    //
    // 0 means "measured, and nothing was lifted" — the ordinary pass of a user
    // with no Garmin watch and no walk in flight. nil means "unknown", and only
    // ever comes from a snapshot written before #214 shipped: `mergingLiveCounters`
    // then falls back to the pre-#214 rule for that one snapshot, so the update
    // itself can't drop a Garmin user's totals in the window before the app or a
    // background wake republishes.
    var floorSteps: Int?
    var floorMinutes: Int?
    var floorDistanceKm: Double?

    static let placeholder = WidgetSnapshot(
        steps: 0, stepsGoal: 6_000, minutes: 0, minutesGoal: 20,
        distanceKm: 0, calories: 0, streak: 0
    )

    init(
        steps: Int,
        stepsGoal: Int,
        minutes: Int,
        minutesGoal: Int,
        distanceKm: Double,
        calories: Int,
        streak: Int,
        waterML: Int = 0,
        waterGoalML: Int = 2_000,
        hydrationEnabled: Bool = false,
        hydrationGlassML: Int = 250,
        day: Date? = nil,
        floorSteps: Int? = nil,
        floorMinutes: Int? = nil,
        floorDistanceKm: Double? = nil
    ) {
        self.steps = steps
        self.stepsGoal = stepsGoal
        self.minutes = minutes
        self.minutesGoal = minutesGoal
        self.distanceKm = distanceKm
        self.calories = calories
        self.streak = streak
        self.waterML = waterML
        self.waterGoalML = waterGoalML
        self.hydrationEnabled = hydrationEnabled
        self.hydrationGlassML = hydrationGlassML
        self.day = day
        self.floorSteps = floorSteps
        self.floorMinutes = floorMinutes
        self.floorDistanceKm = floorDistanceKm
    }

    /// A copy with the daily counters zeroed when the snapshot was written on
    /// another day (or carries no day stamp). Goals, streak and the hydration
    /// toggle survive midnight — only the "today" totals go stale.
    func zeroedIfStale(today: Date = Calendar.current.startOfDay(for: .now)) -> WidgetSnapshot {
        guard day != today else { return self }
        var copy = self
        copy.steps = 0
        copy.minutes = 0
        copy.distanceKm = 0
        copy.calories = 0
        copy.waterML = 0
        // The floor is day-scoped like every overlay that feeds it (#144, #152,
        // #203): what the watch measured yesterday, or a walk taken yesterday,
        // may not hold up a counter today. Zero rather than nil — the counters
        // above are now known-zero, so the floor under them is known-zero too,
        // and nil is reserved for "written before #214" (see the fields).
        copy.floorSteps = 0
        copy.floorMinutes = 0
        copy.floorDistanceKm = 0
        return copy
    }

    /// This snapshot with a widget process's own live HealthKit reads folded
    /// in. A `nil` leg is a read HealthKit refused (locked phone) and keeps the
    /// stored value, as before.
    ///
    /// **`max` against the travelling floor, not against the stored total.**
    /// Steps, minutes and distance are the three counters the app can have
    /// lifted above raw HealthKit before writing them here — the Connect IQ
    /// overlay (#189) and the post-walk `PendingWalk` target (#158) — and the
    /// widget process can measure neither, since it only ever talks to
    /// HealthKit. Overwriting them with the live read would discard both on
    /// every render: a Garmin-only user would see numbers lower than the app's
    /// from the same second, and a walk that just ended would vanish from the
    /// widget the instant `publishToWidgets` reloaded the timeline. So what
    /// those overlays contributed stays a floor — `floor*`, which carries their
    /// combined lift (see the fields).
    ///
    /// That lift, though — and nothing else. Comparing against `self.steps`,
    /// which is itself `max(healthKit, lift)`, also pinned the *purely
    /// HealthKit* part at the day's high: a walk deleted in Santé, or a
    /// duplicate Garmin Connect corrected downwards, stayed on the widget until
    /// the app republished, and for a user with no watch and no walk in flight
    /// the `max` was pure latency for no invariant at all (issue #214).
    /// Comparing against `floor*` instead keeps both guarantees and lets a
    /// legitimate fall through on the next render — the same rule the
    /// background path has always applied (`HealthKitClient+BackgroundDelivery`).
    ///
    /// A `nil` floor is not "no floor", it is "not recorded": only a snapshot
    /// written before #214 shipped has one, and for that snapshot the pre-#214
    /// rule applies unchanged (`?? self.steps`). Reading it as zero instead
    /// would collapse a Garmin user's counters to a not-yet-synced HealthKit on
    /// the first render after the update — briefly the exact #189 symptom this
    /// snapshot exists to prevent. Every snapshot this build writes records the
    /// floor, so the fallback lasts until the first refresh or background wake.
    ///
    /// Never a sum: both terms describe the same day, so this is the `max` the
    /// app applies (`GarminSnapshotOverlay`), with the minutes cap of
    /// `ActiveMinutes`.
    ///
    /// Calories and water are plain overwrites: no overlay ever raises them,
    /// and water legitimately goes *down* when a glass is deleted.
    ///
    /// Call on a `zeroedIfStale()` receiver — the `max` must not have
    /// yesterday's floor on the other side.
    func mergingLiveCounters(
        steps: Int?,
        minutes: Int?,
        distanceKm: Double?,
        calories: Int?,
        waterML: Int?
    ) -> WidgetSnapshot {
        var merged = self
        if let steps { merged.steps = max(steps, floorSteps ?? self.steps) }
        if let minutes { merged.minutes = ActiveMinutes.merged(minutes, with: floorMinutes ?? self.minutes) }
        if let distanceKm { merged.distanceKm = max(distanceKm, floorDistanceKm ?? self.distanceKm) }
        if let calories { merged.calories = calories }
        if let waterML { merged.waterML = waterML }
        return merged
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decode(Int.self, forKey: .steps)
        stepsGoal = try container.decode(Int.self, forKey: .stepsGoal)
        minutes = try container.decode(Int.self, forKey: .minutes)
        minutesGoal = try container.decode(Int.self, forKey: .minutesGoal)
        distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        calories = try container.decode(Int.self, forKey: .calories)
        streak = try container.decode(Int.self, forKey: .streak)
        waterML = try container.decodeIfPresent(Int.self, forKey: .waterML) ?? 0
        waterGoalML = try container.decodeIfPresent(Int.self, forKey: .waterGoalML) ?? 2_000
        hydrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .hydrationEnabled) ?? false
        hydrationGlassML = try container.decodeIfPresent(Int.self, forKey: .hydrationGlassML) ?? 250
        day = try container.decodeIfPresent(Date.self, forKey: .day)
        // Absent on pre-#214 payloads only, and deliberately left nil there
        // rather than defaulted to 0 — see `mergingLiveCounters`.
        floorSteps = try container.decodeIfPresent(Int.self, forKey: .floorSteps)
        floorMinutes = try container.decodeIfPresent(Int.self, forKey: .floorMinutes)
        floorDistanceKm = try container.decodeIfPresent(Double.self, forKey: .floorDistanceKm)
    }
}

/// Read/write the widget snapshot in the shared app-group container.
enum SharedStore {
    static let suiteName = "group.com.eno33.foulee"

    private static let key = "widget.snapshot"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static func write(_ snapshot: WidgetSnapshot) {
        // Stamp the write day so readers can tell today's totals from
        // yesterday's leftovers after midnight.
        var snapshot = snapshot
        snapshot.day = Calendar.current.startOfDay(for: .now)
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Update only today's water intake, preserving the rest of the snapshot —
    /// the hydration flow (app card or notification action) knows the new
    /// intake but not the walk metrics.
    static func updateWater(intakeML: Int) {
        // Zero stale counters first: the first drink of a new day must not
        // resurrect yesterday's steps under today's stamp.
        var snapshot = (read() ?? .placeholder).zeroedIfStale()
        snapshot.waterML = intakeML
        write(snapshot)
    }
}

/// Bridge to the platform-neutral projection input (`WidgetTimelineBuilder`
/// compiles into the watch widget target, this type does not).
extension WidgetSnapshot {
    var counters: WidgetCounters {
        WidgetCounters(
            steps: steps, stepsGoal: stepsGoal,
            minutes: minutes, minutesGoal: minutesGoal,
            distanceKm: distanceKm, calories: calories
        )
    }
}
