@preconcurrency import CoreLocation

/// Continuous fix recorder that draws an outing's route — on the phone's map
/// sheet and on the watch's « Plan » page (issue #312).
///
/// One recorder for both platforms, compiled by both targets: the accuracy
/// rule and the stream lifetime are the parts that can be got wrong, and two
/// copies would be two chances to. It also owns the when-in-use authorization
/// request, so the app has a single place that asks.
///
/// Kept apart from the phone's weather lookup so a walk's high-accuracy
/// streaming never disturbs the kilometre-accuracy one-shot the weather card
/// relies on.
@MainActor
final class RouteRecorder: NSObject, CLLocationManagerDelegate {
    static let shared = RouteRecorder()

    /// Fixes less precise than this are dropped before anything sees them.
    ///
    /// A fix reported 80 m off draws a spike on the map and, once routes reach
    /// Santé, adds distance that was never walked. 50 m keeps the fixes a watch
    /// gets under trees or between buildings while rejecting the cell-tower
    /// guesses CoreLocation hands out before GPS has locked.
    nonisolated static let maximumHorizontalAccuracy: CLLocationAccuracy = 50

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Bool, Never>?
    private var continuation: AsyncStream<CLLocation>.Continuation?
    /// Which stream `continuation` belongs to. A stream superseded by a newer
    /// one terminates *after* the newer one has begun; without this its
    /// termination would stop the newer stream's updates.
    private var streamID: UUID?
    private var acceptedFixes = 0
    private var rejectedFixes = 0

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 8 // metres — enough fidelity for a walk path
        manager.activityType = .fitness
    }

    /// Whether `location` is precise enough to belong on a route. A negative
    /// accuracy is CoreLocation's way of saying the fix is invalid.
    nonisolated static func isUsable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= maximumHorizontalAccuracy
    }

    /// Ask for when-in-use access if it has never been asked, and answer
    /// whether the app may read a position.
    func requestAuthorization() async -> Bool {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status.allowsLocation }
        return await withCheckedContinuation { continuation in
            // Supersede any in-flight auth request so its continuation can't leak.
            authContinuation?.resume(returning: false)
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Stream usable fixes until the consumer stops iterating. Starting a new
    /// stream finishes the previous one.
    nonisolated static func updates() -> AsyncStream<CLLocation> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { _ in
                Task { @MainActor in shared.end(id) }
            }
            Task { @MainActor in shared.begin(id, yielding: continuation) }
        }
    }

    private func begin(_ id: UUID, yielding continuation: AsyncStream<CLLocation>.Continuation) {
        self.continuation?.finish()
        self.continuation = continuation
        streamID = id
        acceptedFixes = 0
        rejectedFixes = 0
        manager.startUpdatingLocation()
    }

    private func end(_ id: UUID) {
        guard streamID == id else { return }
        manager.stopUpdatingLocation()
        continuation = nil
        streamID = nil
        // The one line that says, after an outing, whether the stream held —
        // the question no simulator answers for a wrist that went dark.
        FouleeLog.route.notice(
            "tracé terminé : \(self.acceptedFixes, privacy: .public) points retenus, \(self.rejectedFixes, privacy: .public) écartés"
        )
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let granted = manager.authorizationStatus.allowsLocation
        Task { @MainActor in
            authContinuation?.resume(returning: granted)
            authContinuation = nil
            // A stream opened before the answer came in: updates requested
            // while undetermined are not guaranteed to resume on their own.
            if granted, continuation != nil {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let usable = locations.filter(Self.isUsable)
        let rejected = locations.count - usable.count
        Task { @MainActor in
            acceptedFixes += usable.count
            rejectedFixes += rejected
            for location in usable { continuation?.yield(location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // `locationUnknown` is transient and CoreLocation keeps trying on its
        // own; anything else is worth a line, never a dead stream.
        if (error as? CLError)?.code == .locationUnknown { return }
        FouleeLog.route.error("tracé : \(error.localizedDescription, privacy: .public)")
    }
}
