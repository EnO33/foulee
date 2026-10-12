import Foundation

/// Active minutes accumulated on a single calendar day. Used by the Stats
/// screen and `StreakCalculator`.
nonisolated public struct DailyMinutes: Equatable, Sendable, Identifiable {
    /// Start of the day (local calendar).
    public var date: Date
    public var minutes: Int

    public var id: Date { date }

    public init(
        date: Date,
        minutes: Int
    ) {
        self.date = date
        self.minutes = minutes
    }
}
