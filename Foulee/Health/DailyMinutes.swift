import Foundation

/// Active minutes accumulated on a single calendar day. Used by the Stats
/// screen and `StreakCalculator`.
struct DailyMinutes: Equatable, Sendable, Identifiable {
    /// Start of the day (local calendar).
    var date: Date
    var minutes: Int

    var id: Date { date }
}
