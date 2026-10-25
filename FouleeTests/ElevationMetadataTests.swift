import FouleeKit
import HealthKit
import Testing
@testable import Foulee

/// What a workout is stamped with for its climb and descent (issue #564).
@Suite("Elevation metadata")
struct ElevationMetadataTests {
    private func meters(_ key: String, in metadata: [String: Any]) -> Double? {
        (metadata[key] as? HKQuantity)?.doubleValue(for: .meter())
    }

    @Test("Climb and descent go under their own standard key")
    func bothKeys() {
        let metadata = Elevation(ascent: 120, descent: 115).metadata
        #expect(meters(HKMetadataKeyElevationAscended, in: metadata) == 120)
        #expect(meters(HKMetadataKeyElevationDescended, in: metadata) == 115)
    }

    @Test("Under a metre is not written: absent is not 0 m")
    func underAMetre() {
        let metadata = Elevation(ascent: 0.6, descent: 40).metadata
        #expect(metadata[HKMetadataKeyElevationAscended] == nil)
        #expect(meters(HKMetadataKeyElevationDescended, in: metadata) == 40)
        #expect(Elevation.zero.metadata.isEmpty)
    }
}
