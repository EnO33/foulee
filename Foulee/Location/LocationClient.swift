import Dependencies
import Foundation

/// `CLLocationManager` wrapped as a struct-of-closures. `currentLocation()`
/// returns `nil` when authorization is denied or no fix is available within
/// a reasonable window — never throws on the happy-path "the user said no".
struct LocationClient: Sendable {
    var requestWhenInUse: @Sendable () async -> Bool
    var currentLocation: @Sendable () async -> Coordinate?
}

extension LocationClient: DependencyKey {
    static let previewValue = LocationClient(
        requestWhenInUse: { true },
        currentLocation: { Coordinate(latitude: 48.8566, longitude: 2.3522) }
    )

    static let testValue = LocationClient(
        requestWhenInUse: { false },
        currentLocation: { nil }
    )
}

extension DependencyValues {
    var location: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
