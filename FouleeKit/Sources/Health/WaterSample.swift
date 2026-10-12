import Foundation

/// One drink as Santé stores it (issue #355): a `dietaryWater` sample, from
/// Foulée or from any other app that logs water.
nonisolated public struct WaterSample: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var milliliters: Int
    /// The app or device that wrote it, as Santé names it.
    public var sourceName: String

    public init(
        id: UUID,
        date: Date,
        milliliters: Int,
        sourceName: String
    ) {
        self.id = id
        self.date = date
        self.milliliters = milliliters
        self.sourceName = sourceName
    }
}
