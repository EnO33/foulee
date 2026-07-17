import Foundation

/// Last successful HealthKit reads for the watch complications, stored in the
/// shared app group so the widget extension can fall back to them when a live
/// query fails (protected data after a reboot, transient errors). Each value
/// is stamped with its day: reads from another day return nil, so the cache
/// can never resurrect yesterday's totals after midnight. A legitimate zero
/// is written like any other value — the fallback only applies when the query
/// itself fails, never in place of a real zero.
enum WatchComplicationCache {
    /// Key for the hydration complication's water total, alongside the
    /// WatchStatMetric raw values used by the stat complication.
    static let waterKey = "waterML"

    private struct Stamped: Codable {
        var value: Double
        var day: Date
    }

    private static let keyPrefix = "watch.complication.cache."
    private static let suiteName = "group.com.eno33.foulee"

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // The `defaults` parameter is a test seam: production call sites rely on
    // the default (the app-group suite); tests inject an isolated suite.
    static func write(
        _ value: Double,
        for key: String,
        now: Date = .now,
        to defaults: UserDefaults = Self.sharedDefaults
    ) {
        let stamped = Stamped(value: value, day: Calendar.current.startOfDay(for: now))
        guard let data = try? JSONEncoder().encode(stamped) else { return }
        defaults.set(data, forKey: keyPrefix + key)
    }

    static func read(
        for key: String,
        now: Date = .now,
        from defaults: UserDefaults = Self.sharedDefaults
    ) -> Double? {
        guard let data = defaults.data(forKey: keyPrefix + key),
              let stamped = try? JSONDecoder().decode(Stamped.self, from: data),
              stamped.day == Calendar.current.startOfDay(for: now)
        else { return nil }
        return stamped.value
    }
}
