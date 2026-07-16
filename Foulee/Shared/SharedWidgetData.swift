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
        hydrationGlassML: Int = 250
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
    }
}

/// Read/write the widget snapshot in the shared app-group container.
enum SharedStore {
    static let suiteName = "group.com.eno33.foulee"

    private static let key = "widget.snapshot"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static func write(_ snapshot: WidgetSnapshot) {
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
        var snapshot = read() ?? .placeholder
        snapshot.waterML = intakeML
        write(snapshot)
    }
}
