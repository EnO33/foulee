import Foundation
import HealthKit
import Testing
@testable import Foulee

/// Regression cover for #217: the résumé's filter used to be `.walking`
/// alone, so a runner's seven-day streak faced seven empty days.
///
/// Everything here goes through `recentWorkoutsPredicate` — the exact
/// object `recentWorkoutSummaries` hands to `HKSampleQuery` — and not
/// through the accepted-types constant alone. That distinction is the
/// whole point: asserting the constant still passed with the call site put
/// back to `.walking` (measured: 319 tests, zero failures), because
/// nothing tied the constant to the query.
///
/// The predicate still can't be exercised end to end — HealthKit
/// predicates are only meaningful inside a query against the store, and
/// calling `evaluate(with:)` on one raises an `NSException` (verified: it
/// crashes the test runner, it doesn't just return `false`). So the
/// clauses are read structurally, by rendered format.
@Suite("Workout activity filter")
struct WorkoutActivityFilterTests {
    /// Fixed calendar and clock so the date clause is comparable to one
    /// built here. UTC because `startOfDay` is what shifts under a zone.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
    private static let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func composedPredicate(daysBack: Int = 7) throws -> NSCompoundPredicate {
        let predicate = WorkoutActivityFilter.recentWorkoutsPredicate(
            daysBack: daysBack, calendar: Self.calendar, now: Self.now
        )
        return try #require(predicate as? NSCompoundPredicate)
    }

    /// The activity half of the composed predicate: the OR compound sitting
    /// next to the date clause.
    private func activityClauses() throws -> Set<String> {
        let composed = try composedPredicate()
        #expect(composed.compoundPredicateType == .and)
        let activity = try #require(
            composed.subpredicates
                .compactMap { $0 as? NSCompoundPredicate }
                .first { $0.compoundPredicateType == .or }
        )
        return Set((activity.subpredicates as? [NSPredicate] ?? []).map(\.predicateFormat))
    }

    @Test("The résumé accepts walking, running and hiking — and nothing else")
    func acceptedActivityTypes() {
        #expect(WorkoutActivityFilter.summarizedActivityTypes == [.walking, .running, .hiking])
        #expect(!WorkoutActivityFilter.summarizedActivityTypes.contains(.cycling))
    }

    @Test("The query's predicate carries a run clause — the one #217 was missing")
    func queryPredicateAcceptsRunsAndHikes() throws {
        let clauses = try activityClauses()
        // Compare rendered clauses: both sides come from
        // `predicateForWorkouts(with:)`, so the formats match when — and
        // only when — the same activity type is covered. Spelled out
        // literally rather than mapped over `summarizedActivityTypes`, which
        // would make the assertion true by construction.
        #expect(clauses.contains(HKQuery.predicateForWorkouts(with: .running).predicateFormat))
        #expect(clauses.contains(HKQuery.predicateForWorkouts(with: .hiking).predicateFormat))
        #expect(clauses.contains(HKQuery.predicateForWorkouts(with: .walking).predicateFormat))
        // ORed, not ANDed: an AND over three activity types matches no
        // workout. One clause each, no more — a stray type shows up here.
        #expect(clauses.count == 3)
    }

    @Test("The date clause spans daysBack days back through end of today")
    func datePredicateCoversTheRequestedWindow() throws {
        let composed = try composedPredicate(daysBack: 7)
        let startOfToday = Self.calendar.startOfDay(for: Self.now)
        let expected = HKQuery.predicateForSamples(
            withStart: Self.calendar.date(byAdding: .day, value: -6, to: startOfToday),
            end: startOfToday.addingTimeInterval(24 * 60 * 60),
            options: .strictStartDate
        )
        let formats = composed.subpredicates.compactMap { ($0 as? NSPredicate)?.predicateFormat }
        #expect(formats.contains(expected.predicateFormat))
    }
}
