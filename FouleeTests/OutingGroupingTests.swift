import Foundation
import Testing
@testable import Foulee

/// Cover for #317: an outing the watch split into legs reads as one row of the
/// 7-day résumé.
///
/// Both halves of the rule are pinned, as `WorkoutDeduplicationTests` pins
/// both halves of its own: what must join, and what must stay apart. Joining
/// too eagerly would fold two outings into one and claim kilometres the user
/// ran on another occasion.
@Suite("Outing grouping")
struct OutingGroupingTests {
    /// 2024-05-27 00:00 UTC, as in the deduplication suite.
    private static let anchor = Date(timeIntervalSince1970: 1_716_768_000)

    private func leg(
        _ activity: RecordedActivity,
        from startMinutes: Double,
        lasting minutes: Double,
        outing: OutingLeg? = nil,
        source: String = "Foulée"
    ) -> WorkoutSummary {
        let start = Self.anchor.addingTimeInterval(startMinutes * 60)
        return WorkoutSummary(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            durationSeconds: minutes * 60,
            distanceKm: minutes / 10,
            activeCalories: Int(minutes) * 5,
            steps: Int(minutes) * 100,
            sourceName: source,
            activity: activity,
            outing: outing
        )
    }

    /// Walk → run → walk → run → walk, stamped by the watch: the outing of the
    /// issue, which used to be five rows.
    @Test("Legs sharing an outing are one row, summed over the outing's span")
    func taggedLegsJoin() throws {
        let id = UUID()
        let shape: [(RecordedActivity, Double)] = [(.walking, 10), (.running, 8), (.walking, 5), (.running, 6), (.walking, 12)]
        var start: Double = 480
        let legs = shape.enumerated().map { index, part in
            defer { start += part.1 }
            return leg(part.0, from: start, lasting: part.1, outing: OutingLeg(outingID: id, index: index))
        }

        let rows = OutingGrouping.groupingLegs(legs.shuffled())

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.legs.map(\.id) == legs.map(\.id))
        #expect(row.id == legs[0].id)
        #expect(row.startedAt == legs[0].startedAt)
        #expect(row.endedAt == legs[4].endedAt)
        #expect(row.durationSeconds == TimeInterval(41 * 60))
        #expect(row.steps == 4_100)
        #expect(row.activeCalories == 205)
        #expect(abs(row.distanceKm - 4.1) < 0.000_1)
        // 27 minutes walked against 14 run.
        #expect(row.activity == .walking)
        #expect(row.activityLabel == "Marche et course")
        #expect(row.activityIcon == ActivityGlyph.mixedCardio)
    }

    @Test("Two outings the same day stay two rows, however close")
    func distinctOutingsStayApart() {
        let morning = UUID()
        let noon = UUID()
        let rows = OutingGrouping.groupingLegs([
            leg(.walking, from: 480, lasting: 10, outing: OutingLeg(outingID: morning, index: 0)),
            leg(.running, from: 490, lasting: 10, outing: OutingLeg(outingID: morning, index: 1)),
            // Starts the very second the first ended: only the identifier can
            // tell them apart, and it does.
            leg(.walking, from: 500, lasting: 10, outing: OutingLeg(outingID: noon, index: 0))
        ])
        #expect(rows.map(\.legs.count).sorted() == [0, 2])
    }

    /// Everything recorded before #316 carries no identifier.
    @Test("Untagged legs that touch and change sport are one outing")
    func contiguousLegacyLegsJoin() {
        let rows = OutingGrouping.groupingLegs([
            leg(.walking, from: 480, lasting: 10),
            leg(.running, from: 490, lasting: 10),
            leg(.walking, from: 500, lasting: 10)
        ])
        #expect(rows.count == 1)
        #expect(rows.first?.legs.count == 3)
    }

    @Test("Untagged sessions are not joined across a pause", arguments: [0.5, 5.0])
    func aPauseSeparates(gapMinutes: Double) {
        let rows = OutingGrouping.groupingLegs([
            leg(.walking, from: 480, lasting: 10),
            leg(.running, from: 490 + gapMinutes, lasting: 10)
        ])
        #expect(rows.count == 2)
    }

    /// A leg is made by a change of sport; two walks back to back are two walks.
    @Test("Untagged sessions of the same sport are not joined")
    func sameSportStaysApart() {
        let rows = OutingGrouping.groupingLegs([
            leg(.walking, from: 480, lasting: 10),
            leg(.walking, from: 490, lasting: 10)
        ])
        #expect(rows.count == 2)
    }

    @Test("Untagged sessions from two sources are not joined")
    func twoSourcesStayApart() {
        let rows = OutingGrouping.groupingLegs([
            leg(.walking, from: 480, lasting: 10, source: "Foulée"),
            leg(.running, from: 490, lasting: 10, source: "Strava")
        ])
        #expect(rows.count == 2)
    }

    /// A leg whose stamp was lost — recovered after a crash — still joins the
    /// outing it touches.
    @Test("An untagged leg touching a tagged one joins its outing")
    func untaggedLegJoinsTaggedOuting() {
        let id = UUID()
        let rows = OutingGrouping.groupingLegs([
            leg(.walking, from: 480, lasting: 10, outing: OutingLeg(outingID: id, index: 0)),
            leg(.running, from: 490, lasting: 10)
        ])
        #expect(rows.count == 1)
    }

    @Test("A single session is returned untouched")
    func singleSessionUntouched() {
        let walk = leg(.walking, from: 480, lasting: 30)
        #expect(OutingGrouping.groupingLegs([walk]) == [walk])
        #expect(walk.activityLabel == "Marche")
        #expect(walk.activityIcon == ActivityGlyph.walk)
    }

    @Test("Three sports read as a French list")
    func threeSportLabel() {
        var row = leg(.walking, from: 480, lasting: 10)
        row.legs = [
            leg(.walking, from: 480, lasting: 5),
            leg(.running, from: 485, lasting: 5),
            leg(.hiking, from: 490, lasting: 5),
            leg(.running, from: 495, lasting: 5)
        ]
        #expect(row.activityLabel == "Marche, course et randonnée")
    }

    /// The order the sheet runs the two passes in is the point: a Strava copy
    /// of the whole outing overlaps every leg, and must meet the outing whole.
    @Test("A copy of the outing from another app leaves one row, with its legs")
    func outingBeatsAnUndividedCopy() throws {
        let id = UUID()
        let legs = [
            leg(.walking, from: 480, lasting: 20, outing: OutingLeg(outingID: id, index: 0)),
            leg(.running, from: 500, lasting: 20, outing: OutingLeg(outingID: id, index: 1))
        ]
        // A few seconds longer than the outing: longest-wins alone would pick it.
        let strava = leg(.running, from: 479.9, lasting: 40.2, source: "Strava")

        let rows = WorkoutDeduplication.collapsingOverlaps(OutingGrouping.groupingLegs(legs + [strava]))

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.legs.count == 2)
        #expect(row.sourceName == "Foulée")
    }
}

@Suite("Outing leg metadata")
struct OutingLegMetadataTests {
    /// The phone reads back exactly what the watch wrote (#316).
    @Test("A stamp reads back as the leg it was written from")
    func roundTrip() {
        let leg = OutingLeg(outingID: UUID(), index: 2)
        #expect(OutingLeg(metadata: leg.metadata) == leg)
    }

    @Test("A workout without a stamp, or with a broken one, has no outing")
    func missingOrBroken() {
        #expect(OutingLeg(metadata: nil) == nil)
        #expect(OutingLeg(metadata: [:]) == nil)
        #expect(OutingLeg(metadata: [
            FouleeWorkoutMetadata.outingID: "not-a-uuid",
            FouleeWorkoutMetadata.legIndex: 0
        ]) == nil)
        #expect(OutingLeg(metadata: [FouleeWorkoutMetadata.outingID: UUID().uuidString]) == nil)
    }
}
