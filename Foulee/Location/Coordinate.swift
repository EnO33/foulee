import Foundation

/// Plain `Sendable` 2D coordinate — avoids exporting non-`Sendable`
/// `CLLocation` across dependency boundaries.
nonisolated struct Coordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}
