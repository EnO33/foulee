import Dependencies
import Foundation
import Observation

enum StatsRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "Semaine"
        case .month: "Mois"
        case .year: "Année"
        }
    }

    var daysBack: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        }
    }
}

/// Owns the Stats screen's history + derived streaks. Loads enough history
/// upfront (one year) to feed every range, then filters in-memory when the
/// user flips the segmented control.
@MainActor
@Observable
final class StatsStore {
    private(set) var history: [DailyMinutes] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    var range: StatsRange = .week

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    /// Slice of history matching the active range. For `.week` we align on
    /// the **current ISO week (Mon → Sun)** so the chart's weekday labels
    /// match what users expect, instead of a rolling 7-day window starting
    /// mid-week. `.month` and `.year` stay as rolling windows.
    func filteredHistory() -> [DailyMinutes] {
        switch range {
        case .week: currentWeekSlice()
        case .month, .year:
            Array(history[max(history.count - range.daysBack, 0)...])
        }
    }

    private func currentWeekSlice() -> [DailyMinutes] {
        let calendar = Calendar.iso8601Monday
        let byDay = Dictionary(uniqueKeysWithValues: history.map {
            (calendar.startOfDay(for: $0.date), $0.minutes)
        })
        return ISOWeek.days(containing: .now, calendar: calendar).map {
            DailyMinutes(date: $0, minutes: byDay[$0] ?? 0)
        }
    }

    func currentStreak(goalMinutes: Int, activeDays: Set<Weekday>, today: Date = .now) -> Int {
        StreakCalculator.current(
            history: history,
            goalMinutes: goalMinutes,
            activeWeekdays: activeDays.calendarWeekdays,
            today: today
        )
    }

    func bestStreak(goalMinutes: Int, activeDays: Set<Weekday>) -> Int {
        StreakCalculator.best(
            history: history,
            goalMinutes: goalMinutes,
            activeWeekdays: activeDays.calendarWeekdays
        )
    }

    func totalWalks(goalMinutes: Int) -> Int {
        filteredHistory()
            .lazy
            .filter { $0.minutes >= goalMinutes }
            .count
    }

    func averageMinutes() -> Int {
        let entries = filteredHistory()
        guard !entries.isEmpty else { return 0 }
        let sum = entries.reduce(0) { $0 + $1.minutes }
        return sum / entries.count
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let loaded = await runOrTrap {
            try await healthKit.dailyMinutes(StatsRange.year.daysBack)
        }
        guard let loaded else { return }
        history = loaded
    }

    private func runOrTrap<T: Sendable>(_ body: () async throws -> T) async -> T? {
        do {
            return try await body()
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
