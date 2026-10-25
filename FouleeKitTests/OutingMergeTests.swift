import Foundation
import Testing
@testable import FouleeKit

/// Cover for #550: two outings the wearer said were one read as one row, and
/// nothing merges that should not.
@Suite("Outing merge")
struct OutingMergeTests {
    /// 2024-05-27 00:00 UTC, as in the grouping suite.
    private static let anchor = Date(timeIntervalSince1970: 1_716_768_000)

    private func outing(
        _ activity: RecordedActivity = .walking,
        from startMinutes: Double,
        lasting minutes: Double,
        source: String = "Foulée",
        outing: OutingLeg? = nil
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

    /// The Bilan's own passes, merges first.
    private func rows(_ workouts: [WorkoutSummary], merges: [OutingMerge]) -> [WorkoutSummary] {
        WorkoutDeduplication.collapsingOverlaps(
            OutingGrouping.groupingLegs(OutingMerges.applying(merges, to: workouts))
        )
    }

    // MARK: - What can be merged

    @Test("Two outings an hour apart or less can be merged, in either order")
    func closeOutingsCanMerge() {
        let first = outing(from: 480, lasting: 30)
        let second = outing(from: 570, lasting: 20)
        #expect(OutingMerges.canMerge(first, second))
        #expect(OutingMerges.canMerge(second, first))
    }

    @Test("Two outings more than an hour apart cannot")
    func distantOutingsCannot() {
        #expect(!OutingMerges.canMerge(outing(from: 480, lasting: 30), outing(from: 571, lasting: 20)))
    }

    @Test("Two overlapping outings cannot: that is a copy, not a second part")
    func overlappingOutingsCannot() {
        #expect(!OutingMerges.canMerge(outing(from: 480, lasting: 30), outing(from: 500, lasting: 20)))
    }

    @Test("A Garmin outing Santé doesn't have yet cannot")
    func pendingOutingCannot() {
        let pending = outing(from: 520, lasting: 20, source: GarminPendingOutings.sourceName)
        #expect(!OutingMerges.canMerge(outing(from: 480, lasting: 30), pending))
    }

    @Test("Only the outings right before and right after are offered")
    func neighboursAreTheClosestOnly() {
        let morning = outing(from: 420, lasting: 20)
        let first = outing(from: 480, lasting: 30)
        let target = outing(from: 520, lasting: 20)
        let next = outing(from: 560, lasting: 20)
        let evening = outing(from: 1_080, lasting: 30)

        let neighbours = OutingMerges.neighbours(of: target, in: [evening, next, target, first, morning])

        #expect(neighbours.previous?.id == first.id)
        #expect(neighbours.next?.id == next.id)
    }

    @Test("A neighbour is an outing as listed: a copy of the outing is none")
    func neighboursAreRows() {
        let target = outing(from: 480, lasting: 30)
        let strava = outing(from: 480.1, lasting: 29.8, source: "Strava")
        let next = outing(from: 520, lasting: 20)
        let neighbours = OutingMerges.neighbours(of: target, in: [target, strava, next])
        #expect(neighbours.previous == nil)
        #expect(neighbours.next?.id == next.id)
    }

    @Test("A neighbour too far away is not offered")
    func distantNeighbourIsNotOffered() {
        let target = outing(from: 480, lasting: 30)
        let neighbours = OutingMerges.neighbours(of: target, in: [target, outing(from: 600, lasting: 20)])
        #expect(neighbours.previous == nil)
        #expect(neighbours.next == nil)
    }

    // MARK: - Merging, separating

    @Test("Two merged outings are one row: the whole span, the sum of both")
    func mergedOutingsAreOneRow() throws {
        let first = outing(from: 480, lasting: 30)
        let second = outing(from: 522, lasting: 20)
        let merges = OutingMerges.merging(first, second, in: [])

        let result = rows([second, first], merges: merges)

        let row = try #require(result.first)
        #expect(result.count == 1)
        #expect(row.id == first.id)
        #expect(row.legs.map(\.id) == [first.id, second.id])
        #expect(row.startedAt == first.startedAt)
        #expect(row.endedAt == second.endedAt)
        // The twelve-minute stop is not exercise.
        #expect(row.durationSeconds == TimeInterval(50 * 60))
        #expect(abs(row.distanceKm - 5) < 0.000_1)
        #expect(row.steps == 5_000)
        #expect(row.activityLabel == "Marche")
    }

    @Test("Merging a third outing into a merged pair leaves one merge of three")
    func mergingIntoAMergeExtendsIt() throws {
        let first = outing(from: 480, lasting: 30)
        let second = outing(from: 520, lasting: 20)
        let third = outing(from: 560, lasting: 10)
        let pair = OutingMerges.merging(first, second, in: [])
        let merged = try #require(rows([first, second, third], merges: pair).first { !$0.legs.isEmpty })

        let merges = OutingMerges.merging(merged, third, in: pair)

        #expect(merges.count == 1)
        #expect(merges.first?.workoutIDs == [first.id, second.id, third.id])
        #expect(merges.first?.startedAt == first.startedAt)
        #expect(rows([first, second, third], merges: merges).count == 1)
    }

    @Test("A separated outing reads back as the two it was")
    func separatingUndoesTheMerge() throws {
        let first = outing(from: 480, lasting: 30)
        let second = outing(from: 520, lasting: 20)
        let merges = OutingMerges.merging(first, second, in: [])
        let merged = try #require(rows([first, second], merges: merges).first)
        #expect(OutingMerges.isMerged(merged, in: merges))

        let separated = OutingMerges.separating(merged, in: merges)

        #expect(separated.isEmpty)
        #expect(rows([first, second], merges: separated).count == 2)
    }

    @Test("Separating leaves the other merges alone")
    func separatingKeepsOtherMerges() {
        let morning = OutingMerges.merging(outing(from: 480, lasting: 30), outing(from: 520, lasting: 20), in: [])
        let evening = outing(from: 1_080, lasting: 30)
        let merges = OutingMerges.merging(evening, outing(from: 1_120, lasting: 20), in: morning)

        #expect(OutingMerges.separating(evening, in: merges) == morning)
    }

    @Test("A watch outing regrouped from its legs is not a merge to separate")
    func watchOutingIsNotMerged() throws {
        let id = UUID()
        let legs = [
            outing(.walking, from: 480, lasting: 10, outing: OutingLeg(outingID: id, index: 0)),
            outing(.running, from: 490, lasting: 10, outing: OutingLeg(outingID: id, index: 1))
        ]
        let row = try #require(rows(legs, merges: []).first)
        #expect(!OutingMerges.isMerged(row, in: []))
    }

    @Test("A watch outing merged with the outing after it keeps every leg")
    func watchOutingMergesWhole() throws {
        let id = UUID()
        let legs = [
            outing(.walking, from: 480, lasting: 10, outing: OutingLeg(outingID: id, index: 0)),
            outing(.running, from: 490, lasting: 10, outing: OutingLeg(outingID: id, index: 1))
        ]
        let restart = outing(.running, from: 505, lasting: 15, outing: OutingLeg(outingID: UUID(), index: 0))
        let watchOuting = try #require(rows(legs, merges: []).first)

        let merges = OutingMerges.merging(watchOuting, restart, in: [])
        let result = rows(legs + [restart], merges: merges)

        let row = try #require(result.first)
        #expect(result.count == 1)
        #expect(row.legs.map(\.id) == legs.map(\.id) + [restart.id])
        #expect(row.legs.map(\.outing?.index) == [0, 1, 2])
        #expect(row.activityLabel == "Marche et course")
    }

    // MARK: - Copies from other writers

    @Test("A copy of the second part from another app folds into the merged outing")
    func copyOfALatePartFolds() throws {
        // A long stop: by its duration alone, the merged outing would end at
        // 08:50, well before the copy of its second part begins.
        let first = outing(from: 480, lasting: 30)
        let second = outing(from: 550, lasting: 20)
        let strava = outing(from: 550.1, lasting: 19.8, source: "Strava")
        let merges = OutingMerges.merging(first, second, in: [])

        let result = rows([first, second, strava], merges: merges)

        let row = try #require(result.first)
        #expect(result.count == 1)
        #expect(row.legs.count == 2)
        #expect(row.sourceName == "Foulée")
        #expect(row.durationSeconds == TimeInterval(50 * 60))
    }

    @Test("A copy running past the merged outing adds only what it covers beyond")
    func staggeredCopyAddsItsOwnClock() throws {
        let first = outing(from: 480, lasting: 30)
        let second = outing(from: 550, lasting: 20)
        // Five minutes on after the second part ended.
        let garmin = outing(from: 551, lasting: 24, source: "Garmin Connect")
        let merges = OutingMerges.merging(first, second, in: [])

        let row = try #require(rows([first, second, garmin], merges: merges).first)

        #expect(row.endedAt == garmin.endedAt)
        #expect(row.durationSeconds == TimeInterval(55 * 60))
    }

    // MARK: - Forgetting

    @Test("A merge older than the retention is forgotten")
    func oldMergesAreForgotten() {
        let recent = OutingMerge(workoutIDs: [UUID()], startedAt: Self.anchor)
        let old = OutingMerge(workoutIDs: [UUID()], startedAt: Self.anchor.addingTimeInterval(-OutingMerges.retention))
        #expect(OutingMerges.kept([recent, old], now: Self.anchor.addingTimeInterval(60)) == [recent])
    }

    @Test("A merge reads back as it was written")
    func mergeRoundTrips() throws {
        let merge = OutingMerge(workoutIDs: [UUID(), UUID()], startedAt: Self.anchor)
        let data = try JSONEncoder().encode([merge])
        #expect(try JSONDecoder().decode([OutingMerge].self, from: data) == [merge])
    }
}
