import Foundation

/// One leg's stretch of the route, and the sport it was done as (issue #319).
///
/// The detail map draws one line per segment, each in its activity's colour,
/// so walk → run → walk reads on the map the way it reads on the timeline.
struct RouteSegment: Equatable, Sendable, Identifiable {
    /// The leg's workout id — one segment per leg, never more.
    var id: UUID
    var activity: RecordedActivity
    var coordinates: [Coordinate]

    /// The workouts whose routes make up `summary`'s map: every leg of a
    /// regrouped outing (#317), or the session itself.
    ///
    /// A leg whose route is missing — recorded indoors, location refused, lost
    /// to a crash — is simply absent from the result, which leaves a **gap** on
    /// the map. Joining its neighbours across it would draw a straight line
    /// nobody walked.
    static func sources(of summary: WorkoutSummary) -> [WorkoutSummary] {
        summary.legs.isEmpty ? [summary] : summary.legs
    }
}
