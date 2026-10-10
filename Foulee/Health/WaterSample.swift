import Foundation

/// One drink as Santé stores it (issue #355): a `dietaryWater` sample, from
/// Foulée or from any other app that logs water.
struct WaterSample: Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var milliliters: Int
    /// The app or device that wrote it, as Santé names it.
    var sourceName: String
}
