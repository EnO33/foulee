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
        #expect(accumulator.add(relativeAltitude: 0) == 0)  // first reading = baseline
        #expect(accumulator.add(relativeAltitude: 2) == 0)  // under the threshold
        #expect(accumulator.add(relativeAltitude: 5) == 5)  // +5 since the baseline
        #expect(accumulator.add(relativeAltitude: 3) == 5)  // -2: noise
        #expect(accumulator.add(relativeAltitude: 8) == 8)  // +3 since 5
        #expect(accumulator.gain == 8)
        #expect(accumulator.loss == 0)
    }

    /// The outing of the issue: an hour on the flat, the barometer wobbling
    /// by up to half a metre every second, used to read hundreds of metres.
    @Test("An hour on the flat, with the barometer's noise, climbs nothing")
    func noisyFlatClimbsNothing() {
        let wobble = [0.0, 0.4, -0.3, 0.5, 0.1, -0.5, 0.2, -0.1]
        let readings = (0..<3_600).map { wobble[$0 % wobble.count] }
        let accumulator = accumulated(readings)
        #expect(accumulator.gain == 0)
        #expect(accumulator.loss == 0)
    }

    @Test("A noisy climb then descent gives each its own, close to the terrain")
    func climbThenDescent() {
        // 100 m up then 100 m down, a reading every 10 cm, ±0.4 m of noise.
        let noise = [0.0, 0.4, -0.4, 0.2, -0.2]
        let up = (0...1_000).map { Double($0) / 10 }
        let down = (0...1_000).map { 100 - Double($0) / 10 }
        let readings = (up + down).enumerated().map { $0.element + noise[$0.offset % noise.count] }

        let accumulator = accumulated(readings)

        #expect(abs(accumulator.gain - 100) <= ElevationAccumulator.threshold + 1)
        #expect(abs(accumulator.loss - 100) <= ElevationAccumulator.threshold + 1)
    }

    @Test("A slow drift under the threshold counts nothing")
    func driftUnderThreshold() {
        let accumulator = accumulated(stride(from: 0, through: 2.9, by: 0.1).map { $0 })
        #expect(accumulator.gain == 0)
    }

    @Test("A flat or descending-only walk has zero gain")
    func noGainWhenFlatOrDown() {
        let accumulator = accumulated([10, 4, 4])
        #expect(accumulator.gain == 0)
        #expect(accumulator.loss == 6)
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
