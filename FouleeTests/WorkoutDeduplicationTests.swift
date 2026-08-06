import Foundation
import Testing
@testable import Foulee

/// Cover for #218: the 7-day résumé listed the same outing once per writer
/// (Apple Watch + Garmin Connect, watch + Strava), because it grouped by day
/// and nothing else.
///
/// The suite pins both halves of the rule — what must merge, and just as
/// importantly what must not. Removing the deduplication was measured against
/// it, and so was the opposite mistake (merging spans that merely touch): each
/// direction is caught by its own test.
///
/// `everyGeometryAgreesWithTheRing` is the one that pins acceptance criterion 3.
/// It runs a *table* of geometries on purpose: the single contained pair it used
/// to assert was the one shape where the sheet and the ring cannot disagree, so
/// it stayed green while a staggered pair silently dropped 35 minutes and a pair
/// straddling midnight moved its row to the wrong day.
@Suite("Workout deduplication")
struct WorkoutDeduplicationTests {
    /// Stable anchor, 2024-05-27 00:00 UTC — sessions are placed in minutes
    /// from it so the arithmetic in each test is readable.
    private static let anchor = Date(timeIntervalSince1970: 1_716_768_000)

    private func session(
        from startMinutes: Int,
        lasting minutes: Double,
        source: String,
        id: UUID = UUID(),
        distanceKm: Double = 0
    ) -> WorkoutSummary {
        let start = Self.anchor.addingTimeInterval(Double(startMinutes) * 60)
        return WorkoutSummary(
            id: id,
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            durationSeconds: minutes * 60,
            distanceKm: distanceKm,
            activeCalories: 0,
            sourceName: source
        )
    }

    @Test("The same outing written by two sources is one row")
    func overlappingSourcesCollapse() {
        // 08:00 → 08:45 on the watch, the same outing 08:01 → 08:44 from
        // Garmin Connect: two samples, one run.
        let rows = WorkoutDeduplication.collapsingOverlaps([
            session(from: 480, lasting: 45, source: "Apple Watch"),
            session(from: 481, lasting: 43, source: "Garmin Connect")
        ])
        #expect(rows.count == 1)
        // Longest wins, so the row speaks for the writer that saw the most.
        #expect(rows.first?.sourceName == "Apple Watch")
        // `45 * 60` on its own types as `Int` inside the macro expansion and
        // compares false against the `TimeInterval` — spell the type out.
        #expect(rows.first?.durationSeconds == TimeInterval(45 * 60))
    }

    @Test("Two distinct sessions the same day stay two rows")
    func distinctSessionsSurvive() {
        let rows = WorkoutDeduplication.collapsingOverlaps([
            session(from: 480, lasting: 30, source: "Apple Watch"),
            session(from: 1_080, lasting: 40, source: "Apple Watch")
        ])
        #expect(rows.count == 2)
        // Newest first, the order the sheet renders.
        #expect(rows.map(\.startedAt) == [
            Self.anchor.addingTimeInterval(1_080 * 60),
            Self.anchor.addingTimeInterval(480 * 60)
        ])
    }

    @Test("Back-to-back sessions touch but don't overlap — still two rows")
    func touchingSessionsStayApart() {
        // 10:00 → 10:30 then 10:30 → 11:00: a warm-up walk followed by a run
        // is two things the user did, not one written twice. Spans are
        // half-open, so this pair must not merge.
        let rows = WorkoutDeduplication.collapsingOverlaps([
            session(from: 600, lasting: 30, source: "Apple Watch"),
            session(from: 630, lasting: 30, source: "Apple Watch")
        ])
        #expect(rows.count == 2)
    }

    @Test("Back-to-back across midnight: the ring folds them, the résumé won't")
    func touchingSpansAcrossMidnightAreTheOneRemainingGap() {
        // The single shape `everyGeometryAgreesWithTheRing` cannot include, and
        // it pre-dates #218: `unionedSpans` folds *touching* spans, so 23:30 →
        // 00:00 → 00:30 is one 60-minute span credited to the first day, while
        // the résumé keeps two rows on two days. Pinned rather than fixed —
        // folding the rows would erase a session the user really did twice
        // (criterion 2), and re-attributing the ring would move the streak.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let workouts = [
            session(from: 1_410, lasting: 30, source: "Apple Watch"),
            session(from: 1_440, lasting: 30, source: "Apple Watch")
        ]
        let ring = ActiveMinutes.workoutMinutesByDay(
            workouts.map { ActiveMinutes.WorkoutInterval(start: $0.startedAt, duration: $0.durationSeconds) },
            calendar: calendar
        )
        #expect(ring.values.sorted() == [60])
        #expect(WorkoutDeduplication.collapsingOverlaps(workouts).count == 2)
    }

    @Test("A three-way overlap collapses to a single row")
    func threeWayOverlapCollapses() {
        // Watch, Garmin and Strava chained: A∩B and B∩C while A and C don't
        // touch. The chain is still one outing.
        let rows = WorkoutDeduplication.collapsingOverlaps([
            session(from: 480, lasting: 30, source: "Apple Watch"),
            session(from: 500, lasting: 30, source: "Garmin Connect"),
            session(from: 520, lasting: 35, source: "Strava")
        ])
        #expect(rows.count == 1)
        #expect(rows.first?.sourceName == "Strava")
    }

    @Test("The surviving row keeps its own numbers — nothing is ever summed")
    func mergedRowsAreNeverAdded() {
        let rows = WorkoutDeduplication.collapsingOverlaps([
            session(from: 480, lasting: 45, source: "Apple Watch", distanceKm: 7.2),
            session(from: 481, lasting: 43, source: "Garmin Connect", distanceKm: 7.1)
        ])
        // 14.3 km would be a run the user never did.
        #expect(rows.first?.distanceKm == 7.2)
        #expect(rows.map(\.durationSeconds).reduce(0, +) == TimeInterval(45 * 60))
    }

    /// Two fixed ids, ordered `lowerID` < `higherID` as strings — the last
    /// tie-break compares `uuidString`. Both literals are valid UUIDs, so the
    /// fallbacks never run.
    private static let lowerID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A") ?? UUID()
    private static let higherID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF") ?? UUID()

    @Test("Equal durations: the earliest start wins, then the sample id")
    func tieBreaksAreExplicit() {
        let rows = WorkoutDeduplication.collapsingOverlaps([
            session(from: 482, lasting: 30, source: "Garmin Connect", id: Self.higherID),
            session(from: 480, lasting: 30, source: "Apple Watch", id: Self.lowerID)
        ])
        #expect(rows.first?.sourceName == "Apple Watch")

        // Same duration *and* same start: only the id can decide, and it must
        // decide the same way every time.
        let sameInstant = WorkoutDeduplication.collapsingOverlaps([
            session(from: 480, lasting: 30, source: "Garmin Connect", id: Self.higherID),
            session(from: 480, lasting: 30, source: "Strava", id: Self.lowerID)
        ])
        #expect(sameInstant.count == 1)
        #expect(sameInstant.first?.sourceName == "Strava")
    }

    @Test("Order is stable: the input's order can't change the list")
    func orderingIsDeterministic() {
        let morning = session(from: 480, lasting: 45, source: "Apple Watch")
        let duplicate = session(from: 481, lasting: 43, source: "Garmin Connect")
        let evening = session(from: 1_080, lasting: 20, source: "Strava")

        let expected = WorkoutDeduplication.collapsingOverlaps([morning, duplicate, evening])
        #expect(expected.map(\.sourceName) == ["Strava", "Apple Watch"])
        // Every permutation of the same three samples renders the same list.
        for input in [
            [evening, duplicate, morning],
            [duplicate, morning, evening],
            [morning, evening, duplicate]
        ] {
            #expect(WorkoutDeduplication.collapsingOverlaps(input) == expected)
        }
    }

    /// Minutes from the anchor, so 1_438 is 23:58 and 1_441 is 00:01 the next
    /// day. The first six shapes are one outing written by several sources; the
    /// last two are two sessions the user really did, and must stay two rows.
    private static let geometries: [(String, [(start: Int, minutes: Double)])] = [
        ("contained", [(480, 45), (481, 43)]),
        ("staggered by a minute of clock skew", [(480, 45), (524, 36)]),
        ("chained A∩B, B∩C", [(480, 30), (500, 30), (520, 35)]),
        ("barely overlapping", [(480, 35), (483, 37)]),
        ("straddling midnight, longest copy after it", [(1_438, 5), (1_441, 60)]),
        ("straddling midnight, longest copy before it", [(1_438, 30), (1_441, 25)]),
        ("two real sessions the same day", [(480, 30), (1_080, 40)]),
        ("two real sessions on two days", [(480, 30), (1_920, 40)])
    ]

    @Test("Day by day, the résumé shows the minutes that validated the streak")
    func everyGeometryAgreesWithTheRing() {
        // Acceptance criterion 3 of #218, stated as the invariant it actually
        // is: *per day*, not as one scalar on one day. A merged row covers the
        // group's unioned span, which is the very range the ring counted, so
        // both sides land on the same day with the same minutes.
        var calendar = Calendar(identifier: .gregorian)
        // Pinned: the two midnight shapes below have to straddle midnight on
        // the CI runner's clock as well as the developer's.
        calendar.timeZone = .gmt
        for (name, shape) in Self.geometries {
            let workouts = shape.map { session(from: $0.start, lasting: $0.minutes, source: "\($0.start)") }
            let ring = ActiveMinutes.workoutMinutesByDay(
                workouts.map { ActiveMinutes.WorkoutInterval(start: $0.startedAt, duration: $0.durationSeconds) },
                calendar: calendar
            )
            let sheet = Dictionary(grouping: WorkoutDeduplication.collapsingOverlaps(workouts)) {
                calendar.startOfDay(for: $0.startedAt)
            }.mapValues { rows in rows.reduce(0) { $0 + Int($1.durationSeconds / 60) } }
            #expect(sheet == ring, "\(name)")
        }
    }

    @Test("A merged row covers the group's span, not the winner's alone")
    func mergedRowSpansTheWholeGroup() {
        // 08:00 → 08:45 on the watch and 08:44 → 09:20 from Garmin: one minute
        // of clock skew between two writers. Showing the 45-minute row alone
        // hid 35 minutes the ring had already credited.
        let rows = WorkoutDeduplication.collapsingOverlaps([
            session(from: 480, lasting: 45, source: "Apple Watch"),
            session(from: 524, lasting: 36, source: "Garmin Connect")
        ])
        #expect(rows.count == 1)
        #expect(rows.first?.sourceName == "Apple Watch")
        #expect(rows.first?.startedAt == Self.anchor.addingTimeInterval(480 * 60))
        #expect(rows.first?.endedAt == Self.anchor.addingTimeInterval(560 * 60))
        // 80 minutes of clock, not the 81 that adding the two would invent.
        #expect(rows.first?.durationSeconds == TimeInterval(80 * 60))
    }

    @Test("A zero-length session keeps its row instead of vanishing")
    func zeroLengthSessionsAreKept() {
        let rows = WorkoutDeduplication.collapsingOverlaps([
            session(from: 480, lasting: 0, source: "Apple Watch"),
            session(from: 480, lasting: 30, source: "Garmin Connect")
        ])
        // It covers no clock, so it merges with nothing — but the résumé is a
        // record of what Santé holds, and dropping a sample is not this
        // function's job.
        #expect(rows.count == 2)
    }

    @Test("Empty input stays empty")
    func emptyInput() {
        #expect(WorkoutDeduplication.collapsingOverlaps([]).isEmpty)
    }
}
