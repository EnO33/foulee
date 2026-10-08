import CoreGraphics

/// Which line of a route a finger landed on (issue #319).
///
/// In screen points, not metres: « close enough » is a matter of finger size,
/// and the same 40 m are a hair's breadth zoomed out and half the screen
/// zoomed in. Pure, so the geometry is tested without a map.
enum RouteHitTest {
    /// Roughly half a fingertip.
    static let tolerance: CGFloat = 24

    /// The index of the stroke nearest `point`, if any comes within
    /// `tolerance`; on a tie, the first — the earlier leg.
    static func nearestStroke(
        to point: CGPoint,
        among strokes: [[CGPoint]],
        tolerance: CGFloat = tolerance
    ) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, stroke) in strokes.enumerated() {
            let distance = self.distance(from: point, to: stroke)
            guard distance <= tolerance, distance < (best?.distance ?? .infinity) else { continue }
            best = (index, distance)
        }
        return best?.index
    }

    /// Distance from `point` to the polyline through `vertices`.
    static func distance(from point: CGPoint, to vertices: [CGPoint]) -> CGFloat {
        guard let first = vertices.first else { return .infinity }
        guard vertices.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        return zip(vertices, vertices.dropFirst())
            .map { distance(from: point, toSegment: $0, $1) }
            .min() ?? .infinity
    }

    /// Distance from `point` to the segment `start`–`end`: to the foot of the
    /// perpendicular when it falls inside, to the nearer end otherwise.
    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let along = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + along * dx), point.y - (start.y + along * dy))
    }
}
