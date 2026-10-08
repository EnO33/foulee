@preconcurrency import CoreLocation
import Foundation

/// Bridges the one-shot `CLLocationManager` fix the weather card needs to
/// `async`. MainActor-isolated because `CLLocationManager` wants to be hung
/// off a runloop thread. Authorization goes through `RouteRecorder`, the
/// app's single place that asks.
@MainActor
private final class LocationBridge: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<Coordinate?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async -> Coordinate? {
        guard manager.authorizationStatus.allowsLocation else { return nil }
        return await withCheckedContinuation { continuation in
            // A second request can arrive before CoreLocation answers the first
            // (e.g. a HealthKit observer triggers a refresh mid-fetch). Resume
            // the previous continuation instead of overwriting (and leaking) it.
            locationContinuation?.resume(returning: nil)
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.first.map { Coordinate($0.coordinate) }
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
        requestWhenInUse: { await RouteRecorder.shared.requestAuthorization() },
        currentLocation: { await LocationBridge.shared.currentLocation() },
        routeUpdates: {
            let fixes = RouteRecorder.updates()
            return AsyncStream { continuation in
                let forwarding = Task {
                    for await fix in fixes { continuation.yield(Coordinate(fix.coordinate)) }
                    continuation.finish()
                }
                // Cancelling the forwarder ends its iteration, which is what
                // terminates the recorder's stream and stops the GPS.
                continuation.onTermination = { _ in forwarding.cancel() }
            }
        }
    )
}
