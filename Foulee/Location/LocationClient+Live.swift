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

extension LocationClient {
    static let liveValue: LocationClient = LocationClient(
        requestWhenInUse: { await LocationBridge.shared.requestAuth() },
        currentLocation: { await LocationBridge.shared.currentLocation() }
    )
}
