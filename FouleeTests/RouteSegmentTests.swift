import Foundation
import Testing
@testable import Foulee

/// Which workouts the detail map reads a route from (issue #319).
@Suite("Route segments")
struct RouteSegmentTests {
    private func session(_ activity: RecordedActivity) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            startedAt: .now,
            endedAt: .now,
            durationSeconds: 0,
            distanceKm: 0,
            activeCalories: 0,
            sourceName: "Foulée",
            activity: activity
        )
    }

    @Test("A single session is its own route")
    func singleSession() {
        let walk = session(.walking)
        #expect(RouteSegment.sources(of: walk).map(\.id) == [walk.id])
    }

    /// The row's own id is its first leg's: reading it as well would draw the
    /// first leg twice.
    @Test("A regrouped outing reads each leg's route, in order, and not its own")
    func outingReadsItsLegs() {
        let legs = [session(.walking), session(.running), session(.walking)]
        var row = legs[0]
        row.legs = legs
        #expect(RouteSegment.sources(of: row).map(\.id) == legs.map(\.id))
    }

    @Test("Each element once, where it first appears")
    func firstOccurrences() {
        #expect([RecordedActivity.walking, .running, .walking, .running].firstOccurrences == [.walking, .running])
        #expect([RecordedActivity]().firstOccurrences.isEmpty)
    }
}
