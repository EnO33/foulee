@preconcurrency import CoreMotion
import Foundation

extension Altimeter {
    /// Real CoreMotion-backed implementation. `CMAltimeter` reports barometric
    /// relative altitude (metres since updates began); we accumulate the
    /// positive deltas into elevation gain. Needs `NSMotionUsageDescription`
    /// (already declared for the pedometer).
    static let liveValue: Altimeter = {
        let altimeter = CMAltimeter()
        return Altimeter(
            startUpdates: {
                AsyncStream { continuation in
                    var accumulator = ElevationAccumulator()
                    altimeter.startRelativeAltitudeUpdates(to: .main) { data, _ in
                        guard let data else { return }
                        continuation.yield(accumulator.add(relativeAltitude: data.relativeAltitude.doubleValue))
                    }
                    continuation.onTermination = { _ in altimeter.stopRelativeAltitudeUpdates() }
                }
            },
            stop: { altimeter.stopRelativeAltitudeUpdates() }
        )
    }()
}
