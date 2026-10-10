import Foundation
import Testing
@testable import Foulee

/// Cover for the *integration point* of #218: `OutingDay.days(in:)`
/// deduplicates and only then groups by day.
///
/// `WorkoutDeduplicationTests` pins the algorithm, but nothing pinned the Bilan
/// actually running it, nor the order — both the dedup call and the
/// dedup-before-group ordering could be removed with the whole suite green. The
/// fixture below is the cross-midnight duplicate the ordering exists for: group
/// first and the two copies land in different buckets, where neither can ever
/// see the overlap.
@Suite("Bilan — jours et sorties")
@MainActor
struct OutingDayTests {
    /// 2024-05-28 12:00 UTC. The calendar below is pinned to GMT so "just
    /// before midnight" means the same thing on CI as on a developer's machine.
    private static let now = Date(timeIntervalSince1970: 1_716_897_600)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// Seven days ending on `now`'s.
    private static var week: RecapPeriod {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return RecapPeriod(kind: .week, start: calendar.date(byAdding: .day, value: -7, to: tomorrow)!, end: tomorrow)
    }

    private func days(_ workouts: [WorkoutSummary]) -> [OutingDay] {
        OutingDay.days(in: Self.week, from: workouts, calendar: Self.calendar)
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
        let sections = days([
            session(-722, lasting: 30, source: "Apple Watch"),
            session(-719, lasting: 25, source: "Garmin Connect")
        ])
        #expect(sections.count == 7)
        // Today (05-28) shows the "Aucune séance enregistrée" placeholder: the
        // outing belongs to the day it started, which is where the ring counted
        // it. Grouping before deduplicating put a second row here instead.
        #expect(sections.last?.workouts.isEmpty == true)
        let yesterday = sections.dropLast().last
        #expect(yesterday?.workouts.count == 1)
        #expect(yesterday?.workouts.first?.sourceName == "Apple Watch")
        #expect(yesterday?.workouts.first?.durationSeconds == TimeInterval(30 * 60))
    }

    @Test("Two writers, one outing, one row — and a real second session survives")
    func duplicatesCollapseWhileDistinctSessionsRemain() {
        let sections = days([
            session(-240, lasting: 45, source: "Apple Watch"),
            session(-239, lasting: 43, source: "Garmin Connect"),
            session(-60, lasting: 20, source: "Apple Watch")
        ])
        let today = sections.last
        #expect(today?.workouts.count == 2)
        // Newest first, the order the Bilan's timeline shows them in (#361).
        #expect(today?.workouts.map(\.durationSeconds) == [TimeInterval(20 * 60), TimeInterval(45 * 60)])
    }

    @Test("Every day of the period is there, in order, even without sessions")
    func alwaysSevenDaysEvenWithoutSessions() {
        let sections = days([])
        #expect(sections.count == 7)
        #expect(sections.map(\.workouts.count) == Array(repeating: 0, count: 7))
        let expected = (0..<7).reversed().compactMap {
            Self.calendar.date(byAdding: .day, value: -$0, to: Self.calendar.startOfDay(for: Self.now))
        }
        #expect(sections.map(\.day) == expected)
    }
}

extension OutingDayTests {
    /// The integration point of #317: the Bilan rejoins legs, not only the
    /// algorithm in isolation.
    @Test("An outing split in legs is one row of the Bilan")
    func legsAreOneRow() {
        let id = UUID()
        let start = Self.now.addingTimeInterval(-3_600)
        let legs = [(RecordedActivity.walking, 0.0), (.running, 600)].enumerated().map { index, part in
            WorkoutSummary(
                id: UUID(),
                startedAt: start.addingTimeInterval(part.1),
                endedAt: start.addingTimeInterval(part.1 + 600),
                durationSeconds: 600,
                distanceKm: 1,
                activeCalories: 50,
                sourceName: "Foulée",
                activity: part.0,
                outing: OutingLeg(outingID: id, index: index)
            )
        }
        let sections = days(legs)
        let rows = sections.flatMap(\.workouts)
        #expect(rows.count == 1)
        #expect(rows.first?.legs.count == 2)
    }
}
