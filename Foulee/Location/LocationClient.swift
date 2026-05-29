import Dependencies
import Foundation

/// `CLLocationManager` wrapped as a struct-of-closures. `currentLocation()`
/// returns `nil` when authorization is denied or no fix is available within
/// a reasonable window — never throws on the happy-path "the user said no".
/// `routeUpdates()` streams fixes while a walk is in progress for the map.
struct LocationClient: Sendable {
    var requestWhenInUse: @Sendable () async -> Bool
    var currentLocation: @Sendable () async -> Coordinate?
    var routeUpdates: @Sendable () -> AsyncStream<Coordinate>
}

extension LocationClient: DependencyKey {
    static let previewValue = LocationClient(
        requestWhenInUse: { true },
        currentLocation: { Coordinate(latitude: 48.8566, longitude: 2.3522) },
        routeUpdates: {
            // A short looping stroll around the Tuileries for previews.
            AsyncStream { continuation in
                let path = [
                    Coordinate(latitude: 48.8634, longitude: 2.3270),
                    Coordinate(latitude: 48.8638, longitude: 2.3285),
                    Coordinate(latitude: 48.8641, longitude: 2.3301),
                    Coordinate(latitude: 48.8647, longitude: 2.3318)
                ]
                Task {
                    var index = 0
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        continuation.yield(path[index % path.count])
                        index += 1
                    }
                    continuation.finish()
                }
            }
        }
    )

    static let testValue = LocationClient(
        requestWhenInUse: { false },
        currentLocation: { nil },
        routeUpdates: { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var location: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
