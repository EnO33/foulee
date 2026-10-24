import Foundation
import Testing
@testable import FouleeKit

@Suite("ElevationAccumulator")
struct ElevationAccumulatorTests {
    @Test("Sums only the climbs (positive deltas), ignoring descents")
    func accumulatesGain() {
        var accumulator = ElevationAccumulator()
        #expect(accumulator.add(relativeAltitude: 0) == 0)  // first reading = baseline
        #expect(accumulator.add(relativeAltitude: 5) == 5)  // +5 climb
        #expect(accumulator.add(relativeAltitude: 3) == 5)  // -2 descent ignored
        #expect(accumulator.add(relativeAltitude: 8) == 10) // +5 climb → 10
        #expect(accumulator.gain == 10)
    }

    @Test("A flat or descending-only walk has zero gain")
    func noGainWhenFlatOrDown() {
        var accumulator = ElevationAccumulator()
        _ = accumulator.add(relativeAltitude: 10)
        _ = accumulator.add(relativeAltitude: 4) // down
        _ = accumulator.add(relativeAltitude: 4) // flat
        #expect(accumulator.gain == 0)
    }
}

/// Each leg's climb out of the outing's (issue #535).
@Suite("ClimbTrail")
struct ClimbTrailTests {
    private let start = Date(timeIntervalSince1970: 1_760_961_600)

    private func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    @Test("A leg climbs what the outing gained between its two ends")
    func legClimb() {
        var trail = ClimbTrail()
        trail.record(0, at: at(0))
        trail.record(40, at: at(10))
        trail.record(70, at: at(20))
        trail.record(85, at: at(30))
        #expect(trail.total == 85)
        #expect(trail.climb(from: at(0), to: at(15)) == 40)
        #expect(trail.climb(from: at(15), to: at(30)) == 45)
        #expect(trail.climb(from: at(-5), to: at(40)) == 85)
    }

    @Test("Nothing before the first reading, and no reading rewrites the past")
    func edges() {
        var trail = ClimbTrail()
        #expect(trail.total == 0)
        #expect(trail.climb(from: at(0), to: at(10)) == 0)
        trail.record(30, at: at(10))
        trail.record(5, at: at(5))
        #expect(trail.total == 30)
        #expect(trail.climb(from: at(10), to: at(5)) == 0)
    }
}
