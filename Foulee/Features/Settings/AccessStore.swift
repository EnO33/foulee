import Dependencies
import FouleeKit
import Observation

/// The permissions iOS refused Foulée, for the Réglages page that lists them
/// (issue #611). Read through the clients, so the page never touches
/// CoreLocation, CoreMotion or HealthKit itself.
@Observable
final class AccessStore {
    /// `nil` until read: the home row says nothing rather than « tout est
    /// autorisé » before it knows.
    private(set) var refused: [DegradedState]?

    @ObservationIgnored @Dependency(\.location) private var location
    @ObservationIgnored @Dependency(\.motionActivityHistory) private var motion
    @ObservationIgnored @Dependency(\.healthKit) private var healthKit

    func refresh() async {
        async let location = location.access()
        async let waterWriteDenied = healthKit.waterWriteDenied()
        refused = DegradedState.permissions(
            location: await location,
            motion: motion.access(),
            waterWriteDenied: await waterWriteDenied
        )
    }
}
