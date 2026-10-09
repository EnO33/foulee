import CoreLocation

/// A route thinned to what the other device's map can show (issues #334, #342).
///
/// **Thinned because it is resent whole.** A route rides in every snapshot —
/// a complete state, never a delta — and a fix arrives every second or so: an
/// hour's outing is thousands of points, re-encoded at every send. A map on
/// the other wrist or phone loses nothing at one point every ten metres; the
/// payload loses most of its weight.
///
/// Shared: the watch thins its route for the phone (#334), the phone its route
/// for the watch (#342), by the same rules.
extension MirroredRoutePortion {
    /// The spacing to aim for. A GPS fix is good to a few metres; anything
    /// finer than this only redraws noise.
    static let minimumSpacing: CLLocationDistance = 10
    /// Never more points than this across the whole route, however long the
    /// outing: past it the spacing widens instead.
    static let maximumPoints = 1_500

    /// Every portion, thinned to a common spacing.
    ///
    /// One spacing for the whole outing, so a portion is never drawn finer
    /// than its neighbour — `minimumSpacing`, widened just enough to stay
    /// under `maximumPoints`. Each portion keeps its first and last point, so
    /// junctions shared between two portions still meet.
    static func thinning(
        _ portions: [(activity: SessionActivity, points: [CLLocationCoordinate2D])]
    ) -> [MirroredRoutePortion] {
        let length = portions.reduce(0) { $0 + pathLength($1.points) }
        let spacing = max(minimumSpacing, length / Double(maximumPoints))
        return portions.map {
            MirroredRoutePortion(activity: $0.activity, coordinates: thinned($0.points, spacing: spacing))
        }
    }

    /// Keep a point only once it is `spacing` from the last one kept — and
    /// always the last, which is where the wearer is.
    static func thinned(_ points: [CLLocationCoordinate2D], spacing: CLLocationDistance) -> [Coordinate] {
        guard let first = points.first else { return [] }
        var kept = [first]
        for point in points.dropFirst().dropLast() where distance(kept[kept.count - 1], point) >= spacing {
            kept.append(point)
        }
        if points.count > 1, let last = points.last {
            kept.append(last)
        }
        return kept.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private static func pathLength(_ points: [CLLocationCoordinate2D]) -> CLLocationDistance {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// CoreLocation's own great-circle distance, rather than a formula of ours.
    private static func distance(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
