import FouleeKit
import Foundation

/// The outings saved on the Garmin watch that Santé doesn't have yet (ADR 0009,
/// D2), between the BLE delivery of their summary and the day Garmin Connect
/// writes them to Santé. The rules are `GarminPendingOutings`; this only keeps
/// the list.
///
/// **Persisted, in `UserDefaults.standard`**, like `GarminSnapshotStore` and
/// for the same reasons: iOS wakes the app on BLE activity and kills it again,
/// and no other process reads it. The widgets see the outings through the
/// minutes the app publishes, never through this list.
nonisolated enum GarminPendingOutingStore {
    private static let key = "garmin.connectiq.pendingOutings"

    /// Keeps `summary` once, however many times the watch delivers it.
    static func add(_ summary: GarminSessionSummary, to defaults: UserDefaults = .standard) {
        write(GarminPendingOutings.adding(summary, to: read(from: defaults)), to: defaults)
    }

    /// The outings Santé doesn't cover yet. Those it now covers, or that the
    /// streak can no longer reach, are dropped from the store on the way.
    static func remaining(
        healthKitWorkouts: [ActiveMinutes.WorkoutInterval],
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) -> [GarminSessionSummary] {
        let stored = read(from: defaults)
        let kept = GarminPendingOutings.remaining(stored, healthKitWorkouts: healthKitWorkouts, now: now)
        if kept != stored {
            write(kept, to: defaults)
        }
        return kept
    }

    static func read(from defaults: UserDefaults = .standard) -> [GarminSessionSummary] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([GarminSessionSummary].self, from: data)) ?? []
    }

    private static func write(_ outings: [GarminSessionSummary], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(outings) else { return }
        defaults.set(data, forKey: key)
    }
}
