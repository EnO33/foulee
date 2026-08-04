import Foundation
import Testing
@testable import Foulee

/// Fixtures shared by the streak suites that drive a real `TodayStore`
/// (`TodayStoreTests`, `TodayStoreLateDataTests`).
enum StreakTestSupport {
    /// Minutes recorded on a walked day — comfortably past the 20-minute goal.
    private static let walkedMinutes = 25

    /// 25-minute days at the given `daysAgo` offsets. Absent offsets read as
    /// 0 minutes downstream, i.e. a day Santé never received.
    static func walkedDays(_ offsets: [Int]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: offsets.map { ($0, walkedMinutes) })
    }

    /// `dailyMinutes` stub over a `[daysAgo: minutes]` history.
    ///
    /// Honors `daysBack` like the real query, so a regression to a shallow
    /// fetch fails the way the device did (issue #176: home card said 12, the
    /// calendar sheet said 23) instead of the stub feeding the whole crafted
    /// history regardless of the window.
    ///
    /// Days are kept as offsets and turned into dates **at fetch time**,
    /// against the same clock the store reads a moment later. A test that
    /// refreshes twice therefore stays coherent if midnight falls in between —
    /// fixtures and expectations shift together instead of drifting apart.
    static func windowed(
        _ minutesByOffset: @escaping @Sendable () -> [Int: Int]
    ) -> @Sendable (Int) async throws -> [DailyMinutes] {
        { daysBack in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            return minutesByOffset().compactMap { offset, minutes in
                guard offset < daysBack else { return nil }
                return calendar.date(byAdding: .day, value: -offset, to: today)
                    .map { DailyMinutes(date: $0, minutes: minutes) }
            }
        }
    }

    /// Store with every weekday active, so streak counts don't depend on which
    /// day of the week the test happens to run.
    @MainActor
    static func everyDayStore() throws -> TodayStore {
        let store = TodayStore()
        let suiteName = "StreakTestSupport-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserPreferences(defaults: defaults)
        preferences.activeDays = Set(Weekday.allCases)
        store.apply(preferences: preferences)
        return store
    }
}
