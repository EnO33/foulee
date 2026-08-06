import Foundation
import Testing
@testable import Foulee

/// Cover for the *integration point* of #218: `TodayWorkoutsSheet.sections`
/// deduplicates and only then groups by day.
///
/// `WorkoutDeduplicationTests` pins the algorithm, but nothing pinned the sheet
/// actually running it, nor the order — both the dedup call and the
/// dedup-before-group ordering could be removed with the whole suite green. The
/// fixture below is the cross-midnight duplicate the ordering exists for: group
/// first and the two copies land in different buckets, where neither can ever
/// see the overlap.
@Suite("Résumé 7 jours — sections")
@MainActor
struct TodayWorkoutsSheetSectionsTests {
    /// 2024-05-28 12:00 UTC. The calendar below is pinned to GMT so "just
    /// before midnight" means the same thing on CI as on a developer's machine.
    private static let now = Date(timeIntervalSince1970: 1_716_897_600)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func session(_ offsetMinutes: Int, lasting minutes: Double, source: String) -> WorkoutSummary {
        let start = Self.now.addingTimeInterval(Double(offsetMinutes) * 60)
        return WorkoutSummary(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            durationSeconds: minutes * 60,
            distanceKm: 5,
            activeCalories: 300,
            sourceName: source
        )
    }

    @Test("One outing straddling midnight is one row, on the day it began")
    func crossMidnightDuplicateIsOneRowOnTheEarlierDay() {
        // 05-27 23:58 on the watch, the same outing from Garmin at 05-28 00:01.
        let sections = TodayWorkoutsSheet.sections(
            from: [
                session(-722, lasting: 30, source: "Apple Watch"),
                session(-719, lasting: 25, source: "Garmin Connect")
            ],
            calendar: Self.calendar,
            now: Self.now
        )
        #expect(sections.count == 7)
        // Today (05-28) shows the "Aucune séance enregistrée" placeholder: the
        // outing belongs to the day it started, which is where the ring counted
        // it. Grouping before deduplicating put a second row here instead.
        #expect(sections.first?.workouts.isEmpty == true)
        let yesterday = sections.dropFirst().first
        #expect(yesterday?.workouts.count == 1)
        #expect(yesterday?.workouts.first?.sourceName == "Apple Watch")
        #expect(yesterday?.workouts.first?.durationSeconds == TimeInterval(30 * 60))
    }

    @Test("Two writers, one outing, one row — and a real second session survives")
    func duplicatesCollapseWhileDistinctSessionsRemain() {
        let sections = TodayWorkoutsSheet.sections(
            from: [
                session(-240, lasting: 45, source: "Apple Watch"),
                session(-239, lasting: 43, source: "Garmin Connect"),
                session(-60, lasting: 20, source: "Apple Watch")
            ],
            calendar: Self.calendar,
            now: Self.now
        )
        let today = sections.first
        #expect(today?.workouts.count == 2)
        // Newest first, the order the sheet renders.
        #expect(today?.workouts.map(\.durationSeconds) == [TimeInterval(20 * 60), TimeInterval(45 * 60)])
    }

    @Test("The window is always seven consecutive days, newest first")
    func alwaysSevenDaysEvenWithoutSessions() {
        let sections = TodayWorkoutsSheet.sections(from: [], calendar: Self.calendar, now: Self.now)
        #expect(sections.count == 7)
        #expect(sections.map(\.workouts.count) == Array(repeating: 0, count: 7))
        let expected = (0..<7).compactMap {
            Self.calendar.date(byAdding: .day, value: -$0, to: Self.calendar.startOfDay(for: Self.now))
        }
        #expect(sections.map(\.day) == expected)
    }
}
