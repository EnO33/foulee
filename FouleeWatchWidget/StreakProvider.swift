@preconcurrency import HealthKit
import WidgetKit

/// Pulls 30 days of `appleExerciseTime` from HealthKit, runs
/// `StreakCalculator.current` against the user's minutes goal, and
/// rebuilds the timeline every 2 hours.
///
/// HealthKit authorization is granted on first launch of the Watch app —
/// the widget process inherits that grant via the bundle ID prefix.
struct StreakProvider: TimelineProvider {
    private static let goalMinutes = 20
    private static let historyDays = 30
    /// Background refresh cadence. Widgets prefer apps to call
    /// `WidgetCenter.shared.reloadAllTimelines()` from inside the app
    /// when the underlying data changes; this fallback exists for the
    /// case where the user never opens the app for a while. 1 h is a
    /// reasonable upper bound for a streak counter — anything fresher
    /// burns battery for marginal benefit.
    private static let refreshInterval: TimeInterval = 60 * 60

    func placeholder(in context: Context) -> StreakEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        let box = SendableBox(value: completion)
        Task {
            let streak = await Self.fetchCurrentStreak()
            box.value(StreakEntry(date: .now, streak: streak))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let box = SendableBox(value: completion)
        Task {
            let streak = await Self.fetchCurrentStreak()
            let entry = StreakEntry(date: .now, streak: streak)
            let nextRefresh = Date(timeIntervalSinceNow: Self.refreshInterval)
            box.value(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private static func fetchCurrentStreak() async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let history = await loadHistory()
        // Use the phone-synced goal + active days (shared app group) so the
        // complication matches the phone — skipping rest days instead of
        // counting every day as active. Falls back until the first sync lands.
        if let sync = WatchSyncStore.read() {
            return StreakCalculator.current(
                history: history,
                goalMinutes: sync.minutesGoal,
                activeWeekdays: Set(sync.activeWeekdays),
                today: .now
            )
        }
        return StreakCalculator.current(
            history: history,
            goalMinutes: goalMinutes,
            today: .now
        )
    }

    private static func loadHistory() async -> [DailyMinutes] {
        do {
            return try await dailyExerciseMinutes(daysBack: Self.historyDays)
        } catch {
            return []
        }
    }

    private static func dailyExerciseMinutes(daysBack: Int) async throws -> [DailyMinutes] {
        let store = HKHealthStore()
        let minutesType = HKQuantityType(.appleExerciseTime)
        let calendar = Calendar.current
        let endOfToday = calendar.startOfDay(for: .now).addingTimeInterval(24 * 60 * 60)
        guard let startOfRange = calendar.date(
            byAdding: .day, value: -(daysBack - 1), to: calendar.startOfDay(for: .now)
        ) else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfRange, end: endOfToday, options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: minutesType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startOfRange,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var output: [DailyMinutes] = []
                results?.enumerateStatistics(from: startOfRange, to: endOfToday) { statistic, _ in
                    let minutes = statistic.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                    output.append(DailyMinutes(date: statistic.startDate, minutes: Int(minutes)))
                }
                continuation.resume(returning: output)
            }
            store.execute(query)
        }
    }
}
