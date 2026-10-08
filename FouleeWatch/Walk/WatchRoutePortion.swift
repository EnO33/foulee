import CoreLocation

/// One leg's stretch of the route, in the sport it was done as (issue #320).
struct WatchRoutePortion: Identifiable {
    /// The leg's id, so a portion keeps its identity as fixes arrive.
    var id: UUID
    var activity: SessionActivity
    var coordinates: [CLLocationCoordinate2D]
}

extension WatchRoutePortion {
    /// Identity of the single portion drawn when the outing has no legs yet —
    /// the seeded capture session, or the instant before the first batch.
    private static let soloID = UUID()

    /// Cut the outing's fixes at its legs' boundaries.
    ///
    /// **Linear, in one pass**: the « Plan » page calls this on every new fix,
    /// and an hour's walk is thousands of them — refiltering the whole route
    /// once per leg on each render would grow with the square of the outing.
    /// Fixes are in time order, so a leg index only ever moves forward.
    ///
    /// A fix belongs to the last leg that **started** at or before it — the
    /// boundary between two legs is the next one's start, which also covers
    /// the leg in flight, whose end is not known yet.
    ///
    /// **The junction belongs to both portions**: each portion after the first
    /// opens on the last point of the one before, or the line would break at
    /// every change of sport.
    ///
    /// - Parameter current: what the screen says is being done now. On the
    ///   live page it names the leg in flight, which follows detection at once
    ///   while the recording waits (`WatchWorkoutStore.applySwitch`) — the
    ///   line must agree with the word on the session page. `nil` on the
    ///   recap, where every leg is closed and named for good.
    static func portions(
        of fixes: [CLLocation],
        legs: [WatchWorkoutSegment],
        current: SessionActivity?
    ) -> [WatchRoutePortion] {
        guard !fixes.isEmpty else { return [] }
        guard !legs.isEmpty else {
            return [WatchRoutePortion(id: soloID, activity: current ?? .walking, coordinates: fixes.map(\.coordinate))]
        }
        var portions = legs.map { WatchRoutePortion(id: $0.id, activity: $0.activity, coordinates: []) }
        if let current, legs[legs.count - 1].end == nil {
            portions[portions.count - 1].activity = current
        }
        var index = 0
        var lastPoint: CLLocationCoordinate2D?
        for fix in fixes {
            var moved = false
            while index < legs.count - 1, fix.timestamp >= legs[index + 1].start {
                index += 1
                moved = true
            }
            if moved, let lastPoint {
                portions[index].coordinates.append(lastPoint)
            }
            portions[index].coordinates.append(fix.coordinate)
            lastPoint = fix.coordinate
        }
        return portions.filter { $0.coordinates.count >= 2 }
    }
}
