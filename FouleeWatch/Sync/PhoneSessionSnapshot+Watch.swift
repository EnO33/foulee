import CoreLocation
import Foundation

/// The phone's session in the wrist's own types (issue #342), so its screens
/// are the very pages of a watch session rather than look-alikes.
extension PhoneSessionSnapshot {
    /// The figures, as the session metrics page reads them. No heart rate: the
    /// phone has no sensor for it, and the page shows a dash for « none ».
    var metrics: WatchWorkoutMetrics {
        var metrics = WatchWorkoutMetrics.empty(for: activity)
        metrics.elapsed = elapsed
        metrics.steps = steps
        metrics.distanceMeters = distanceMeters
        metrics.activeCalories = activeCalories
        metrics.timerBasis = timerBasis
        metrics.activityTotals = WatchActivityTotals(
            elapsed: elapsed,
            steps: steps,
            distanceMeters: distanceMeters,
            activeCalories: activeCalories
        )
        return metrics
    }

    /// The route, as the watch's map line draws it. Identities follow the
    /// portion's position, so a line keeps its identity from one state to the
    /// next.
    var routePortions: [WatchRoutePortion] {
        route.enumerated().compactMap { index, portion in
            guard portion.coordinates.count >= 2 else { return nil }
            return WatchRoutePortion(
                id: Self.portionID(at: index),
                activity: portion.activity,
                coordinates: portion.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            )
        }
    }

    private static func portionID(at index: Int) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: UInt64(index).bigEndian) { bytes.replaceSubrange(8..<16, with: $0) }
        return NSUUID(uuidBytes: bytes) as UUID
    }
}
