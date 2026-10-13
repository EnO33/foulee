import CoreLocation

/// Where a route passes each kilometre, and which way it runs there (issue
/// #452).
///
/// The distance is the route's own, measured along what is drawn: a leg
/// without a route (indoors, location refused) is a gap on the map and adds
/// nothing, so a pastille always sits on a line, never in a gap.
nonisolated public enum RouteMarks {
    public struct Mark: Equatable, Sendable {
        public let coordinate: Coordinate
        /// Degrees clockwise from north, the way the route runs here.
        public let bearing: Double
    }

    /// Kilometres between two marks.
    static let spacing: CLLocationDistance = 1_000

    /// The heading is read over this much of the route either side of a mark:
    /// a GPS fix every metre or two turns a single step's heading into noise.
    static let bearingSpan: CLLocationDistance = 25

    /// One mark at each whole kilometre: the first is kilometre 1.
    public static func kilometres(along paths: [[Coordinate]]) -> [Mark] {
        marks(along: paths, from: spacing)
    }

    /// One arrow halfway between two kilometres, so it never sits under a
    /// pastille: at 500 m, 1.5 km, 2.5 km…
    public static func arrows(along paths: [[Coordinate]]) -> [Mark] {
        marks(along: paths, from: spacing / 2)
    }

    private static func marks(along paths: [[Coordinate]], from first: CLLocationDistance) -> [Mark] {
        let measured = measure(paths)
        guard let length = measured.last?.end else { return [] }
        return stride(from: first, through: length, by: spacing).compactMap { distance in
            guard let path = measured.first(where: { $0.end >= distance }) else { return nil }
            let before = path.point(at: max(path.start, distance - bearingSpan))
            let after = path.point(at: min(path.end, distance + bearingSpan))
            return Mark(coordinate: path.point(at: distance), bearing: bearing(from: before, to: after))
        }
    }

    /// Each path with the distance travelled at each of its points, counted
    /// from the start of the route. A gap between two paths counts for nothing.
    private static func measure(_ paths: [[Coordinate]]) -> [MeasuredPath] {
        var measured: [MeasuredPath] = []
        var travelled: CLLocationDistance = 0
        for points in paths where points.count > 1 {
            var distances = [travelled]
            for (from, to) in zip(points, points.dropFirst()) {
                travelled += distance(from, to)
                distances.append(travelled)
            }
            measured.append(MeasuredPath(points: points, distances: distances))
        }
        return measured
    }

    /// CoreLocation's own great-circle distance, rather than a formula of ours.
    private static func distance(_ from: Coordinate, _ to: Coordinate) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    /// The initial great-circle bearing, in degrees clockwise from north.
    static func bearing(from origin: Coordinate, to target: Coordinate) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = target.latitude * .pi / 180
        let deltaLon = (target.longitude - origin.longitude) * .pi / 180
        let east = sin(deltaLon) * cos(lat2)
        let north = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(east, north) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// One path of the route, with the distance travelled at each point.
nonisolated private struct MeasuredPath {
    let points: [Coordinate]
    /// Same count as `points`, from the start of the whole route.
    let distances: [CLLocationDistance]

    var start: CLLocationDistance { distances.first ?? 0 }
    var end: CLLocationDistance { distances.last ?? 0 }

    /// The point `distance` along the route, between the two fixes around it.
    func point(at distance: CLLocationDistance) -> Coordinate {
        guard let index = distances.indices.dropFirst().first(where: { distances[$0] >= distance }) else {
            return points[points.count - 1]
        }
        let from = points[index - 1]
        let to = points[index]
        let step = distances[index] - distances[index - 1]
        let fraction = step > 0 ? (distance - distances[index - 1]) / step : 0
        return Coordinate(
            latitude: from.latitude + (to.latitude - from.latitude) * fraction,
            longitude: from.longitude + (to.longitude - from.longitude) * fraction
        )
    }
}
