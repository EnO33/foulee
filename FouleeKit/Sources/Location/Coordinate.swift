import Foundation

/// Plain `Sendable` 2D coordinate — avoids exporting non-`Sendable`
/// `CLLocation` across dependency boundaries.
nonisolated public struct Coordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
