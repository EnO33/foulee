import Foundation
import Testing
@testable import FouleeKit

/// Cover for #563: the barometer's noise is not a climb.
@Suite("ElevationAccumulator")
struct ElevationAccumulatorTests {
    /// Feeds `readings` in order, from a fresh accumulator.
    private func accumulated(_ readings: [Double]) -> ElevationAccumulator {
        var accumulator = ElevationAccumulator()
        for reading in readings {
            _ = accumulator.add(relativeAltitude: reading)
        }
        return accumulator
    }

    @Test("A climb counts once past the threshold, whole")
    func accumulatesGain() {
        var accumulator = ElevationAccumulator()
        #expect(accumulator.add(relativeAltitude: 0).ascent == 0)  // first reading = baseline
        #expect(accumulator.add(relativeAltitude: 2).ascent == 0)  // under the threshold
        #expect(accumulator.add(relativeAltitude: 5).ascent == 5)  // +5 since the baseline
        #expect(accumulator.add(relativeAltitude: 3).ascent == 5)  // -2: noise
        #expect(accumulator.add(relativeAltitude: 8).ascent == 8)  // +3 since 5
        #expect(accumulator.elevation == Elevation(ascent: 8, descent: 0))
    }

    /// The outing of the issue: an hour on the flat, the barometer wobbling
    /// by up to half a metre every second, used to read hundreds of metres.
    @Test("An hour on the flat, with the barometer's noise, climbs nothing")
    func noisyFlatClimbsNothing() {
        let wobble = [0.0, 0.4, -0.3, 0.5, 0.1, -0.5, 0.2, -0.1]
        let readings = (0..<3_600).map { wobble[$0 % wobble.count] }
        let accumulator = accumulated(readings)
        #expect(accumulator.elevation.ascent == 0)
        #expect(accumulator.elevation.descent == 0)
    }

    @Test("A noisy climb then descent gives each its own, close to the terrain")
    func climbThenDescent() {
        // 100 m up then 100 m down, a reading every 10 cm, ±0.4 m of noise.
        let noise = [0.0, 0.4, -0.4, 0.2, -0.2]
        let up = (0...1_000).map { Double($0) / 10 }
        let down = (0...1_000).map { 100 - Double($0) / 10 }
        let readings = (up + down).enumerated().map { $0.element + noise[$0.offset % noise.count] }

        let accumulator = accumulated(readings)

        #expect(abs(accumulator.elevation.ascent - 100) <= ElevationAccumulator.threshold + 1)
        #expect(abs(accumulator.elevation.descent - 100) <= ElevationAccumulator.threshold + 1)
    }

    @Test("A slow drift under the threshold counts nothing")
    func driftUnderThreshold() {
        let accumulator = accumulated(stride(from: 0, through: 2.9, by: 0.1).map { $0 })
        #expect(accumulator.elevation.ascent == 0)
    }

    @Test("A flat or descending-only walk has zero gain")
    func noGainWhenFlatOrDown() {
        let accumulator = accumulated([10, 4, 4])
        #expect(accumulator.elevation.ascent == 0)
        #expect(accumulator.elevation.descent == 6)
    }
}

/// Each leg's climb and descent out of the outing's (issues #535, #564).
@Suite("ClimbTrail")
struct ClimbTrailTests {
    private let start = Date(timeIntervalSince1970: 1_760_961_600)

    private func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    private func up(_ ascent: Double, down descent: Double = 0) -> Elevation {
        Elevation(ascent: ascent, descent: descent)
    }

    @Test("A leg climbs and descends what the outing did between its two ends")
    func legClimb() {
        var trail = ClimbTrail()
        trail.record(up(0), at: at(0))
        trail.record(up(40), at: at(10))
        trail.record(up(70, down: 10), at: at(20))
        trail.record(up(85, down: 60), at: at(30))
        #expect(trail.total == up(85, down: 60))
        #expect(trail.elevation(from: at(0), to: at(15)) == up(40))
        #expect(trail.elevation(from: at(15), to: at(30)) == up(45, down: 60))
        #expect(trail.elevation(from: at(-5), to: at(40)) == up(85, down: 60))
    }

    @Test("Nothing before the first reading, and no reading rewrites the past")
    func edges() {
        var trail = ClimbTrail()
        #expect(trail.total == .zero)
        #expect(trail.elevation(from: at(0), to: at(10)) == .zero)
        trail.record(up(30), at: at(10))
        trail.record(up(5), at: at(5))
        #expect(trail.total == up(30))
        #expect(trail.elevation(from: at(10), to: at(5)) == .zero)
    }
}

@Suite("Elevation")
struct ElevationTests {
    @Test("Two stretches add up climb with climb, descent with descent")
    func adding() {
        var total = Elevation(ascent: 10, descent: 4)
        total += Elevation(ascent: 5, descent: 6)
        #expect(total == Elevation(ascent: 15, descent: 10))
    }
}
