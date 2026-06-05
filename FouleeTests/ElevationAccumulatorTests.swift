import Testing
@testable import Foulee

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
