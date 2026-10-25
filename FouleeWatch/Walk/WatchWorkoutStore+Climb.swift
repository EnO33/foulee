import FouleeKit
import Foundation

/// Each leg's share of the outing's climb and descent (issues #535, #564).
extension WatchWorkoutStore {
    /// Stamp the leg closing at `end` with the climb and descent since
    /// `start`, before it is saved. **Never a reason to lose the leg**: a
    /// stamp HealthKit refuses costs the climb, logged, and the save goes on.
    func stampClimb(on handle: WatchWorkoutSessionHandle, from start: Date, to end: Date) async {
        let elevation = climb.trail.elevation(from: start, to: end)
        // Under a metre is the barometer's noise, and no climb is no stamp:
        // the phone reads a missing one as « not measured ».
        guard elevation.ascent >= 1 || elevation.descent >= 1 else { return }
        do {
            try await handle.addClimb(elevation)
        } catch {
            FouleeLog.session.error("dénivelé non enregistré : \(error.localizedDescription, privacy: .public)")
        }
    }
}
