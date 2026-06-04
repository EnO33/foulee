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
    var date: Date
    var steps: Int
    var stepsGoal: Int
    var minutes: Int
    var minutesGoal: Int
    var distanceKm: Double
    var calories: Int
    var streak: Int

    static let placeholder = WidgetSnapshot(
        date: .now, steps: 0, stepsGoal: 6_000, minutes: 0, minutesGoal: 20,
        distanceKm: 0, calories: 0, streak: 0
    )
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
}
