@preconcurrency import CoreLocation
import Foundation

/// Bridges `CLLocationManager` callbacks to `async` via two re-issuable
/// continuations. MainActor-isolated because `CLLocationManager` wants
/// to be hung off a runloop thread.
@MainActor
private final class LocationBridge: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Bool, Never>?
    private var locationContinuation: CheckedContinuation<Coordinate?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestAuth() async -> Bool {
        let status = manager.authorizationStatus
        if status != .notDetermined {
            return status == .authorizedWhenInUse || status == .authorizedAlways
        }
        return await withCheckedContinuation { continuation in
            // Supersede any in-flight auth request so its continuation can't leak.
            authContinuation?.resume(returning: false)
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async -> Coordinate? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            // A second request can arrive before CoreLocation answers the first
            // (e.g. a HealthKit observer triggers a refresh mid-fetch). Resume
            // the previous continuation instead of overwriting (and leaking) it.
            locationContinuation?.resume(returning: nil)
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let granted = status == .authorizedWhenInUse || status == .authorizedAlways
        Task { @MainActor in
            authContinuation?.resume(returning: granted)
            authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.first.map {
            Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        Task { @MainActor in
            locationContinuation?.resume(returning: coord)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}

extension LocationBridge {
    /// Single shared bridge — `@MainActor` so it can keep its delegate
    /// continuations safely. Lazy via Swift's static-let semantics; first
    /// access happens from `TodayStore` which is already `@MainActor`.
    @MainActor static let shared = LocationBridge()
}

/// Continuous fix recorder used to draw the walk's route. Kept separate from
/// `LocationBridge` so the walk's high-accuracy streaming never disturbs the
/// kilometre-accuracy one-shot the weather card relies on.
@MainActor
private final class RouteRecorder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<Coordinate>.Continuation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 8 // metres — enough fidelity for a walk path
        manager.activityType = .fitness
    }

    /// Adopt a new stream (finishing any prior one) and start streaming fixes.
    func begin(yielding continuation: AsyncStream<Coordinate>.Continuation) {
        self.continuation?.finish()
        self.continuation = continuation
        manager.startUpdatingLocation()
    }

    func end() {
        manager.stopUpdatingLocation()
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coords = locations.map {
            Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        Task { @MainActor in
            for coord in coords { self.continuation?.yield(coord) }
        }
    }

    @MainActor static let shared = RouteRecorder()
}

extension LocationClient {
    static let liveValue: LocationClient = LocationClient(
        requestWhenInUse: { await LocationBridge.shared.requestAuth() },
        currentLocation: { await LocationBridge.shared.currentLocation() },
        routeUpdates: {
            // Hop to the main actor for all CLLocationManager work; the stream
            // itself can be built and returned from any thread.
            AsyncStream { continuation in
                Task { @MainActor in RouteRecorder.shared.begin(yielding: continuation) }
                continuation.onTermination = { _ in
                    Task { @MainActor in RouteRecorder.shared.end() }
                }
            }
        }
    )
}
