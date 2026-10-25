import FouleeKit
import HealthKit

nonisolated extension Elevation {
    /// The climb and the descent as a workout's metadata, the standard keys
    /// Santé and other apps read (issue #564). Shared by both writers — the
    /// phone's `saveWorkout` and each watch leg — like `hkActivityType`.
    ///
    /// Under a metre is left out: the phone reads a missing key as « not
    /// measured », and 0 m would read as a flat outing.
    var metadata: [String: Any] {
        var metadata: [String: Any] = [:]
        if ascent >= 1 {
            metadata[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: ascent)
        }
        if descent >= 1 {
            metadata[HKMetadataKeyElevationDescended] = HKQuantity(unit: .meter(), doubleValue: descent)
        }
        return metadata
    }
}
