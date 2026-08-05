import Foundation
import Testing
@testable import Foulee

@Suite("WidgetSnapshot")
struct WidgetSnapshotTests {
    private let today = Calendar.current.startOfDay(for: .now)

    /// The app group as the app left it: counters already merged, and how much
    /// of them the widget process cannot re-measure travelling alongside (#214).
    /// The three default to nil — a payload from a build that predates #214.
    private func snapshot(
        day: Date?,
        floorSteps: Int? = nil,
        floorMinutes: Int? = nil,
        floorDistanceKm: Double? = nil
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            steps: 4_200, stepsGoal: 6_000, minutes: 25, minutesGoal: 20,
            distanceKm: 3.1, calories: 180, streak: 7,
            waterML: 750, waterGoalML: 1_500, hydrationEnabled: true,
            day: day,
            floorSteps: floorSteps,
            floorMinutes: floorMinutes,
            floorDistanceKm: floorDistanceKm
        )
    }

    @Test("Same-day snapshot is returned unchanged")
    func sameDayNoOp() {
        let fresh = snapshot(day: today).zeroedIfStale(today: today)
        #expect(fresh.steps == 4_200)
        #expect(fresh.minutes == 25)
        #expect(fresh.distanceKm == 3.1)
        #expect(fresh.calories == 180)
        #expect(fresh.waterML == 750)
    }

    @Test("Stale snapshot zeroes the daily counters, keeps the rest")
    func staleDayZeroesCounters() throws {
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        let zeroed = snapshot(day: yesterday, floorSteps: 9_000, floorMinutes: 40, floorDistanceKm: 7)
            .zeroedIfStale(today: today)
        // The floor is day-scoped like the counters it holds up (#214), and
        // lands on zero rather than nil: those counters are now known-zero, so
        // the lift under them is known-zero too. nil would mean "unrecorded",
        // which is reserved for payloads written before #214.
        #expect(zeroed.floorSteps == 0)
        #expect(zeroed.floorMinutes == 0)
        #expect(zeroed.floorDistanceKm == 0)
        #expect(zeroed.steps == 0)
        #expect(zeroed.minutes == 0)
        #expect(zeroed.distanceKm == 0)
        #expect(zeroed.calories == 0)
        #expect(zeroed.waterML == 0)
        // Goals, streak and settings survive midnight.
        #expect(zeroed.stepsGoal == 6_000)
        #expect(zeroed.minutesGoal == 20)
        #expect(zeroed.streak == 7)
        #expect(zeroed.waterGoalML == 1_500)
        #expect(zeroed.hydrationEnabled)
    }

    @Test("Snapshot without a day stamp is treated as stale")
    func nilDayIsStale() {
        let zeroed = snapshot(day: nil).zeroedIfStale(today: today)
        #expect(zeroed.steps == 0)
        #expect(zeroed.waterML == 0)
        #expect(zeroed.streak == 7)
    }

    // MARK: - Live widget-process reads folded onto the stored snapshot

    @Test("A live read never discards a counter only the app could measure")
    func liveReadMergesWithTheStoredOverlay() {
        // The whole point of the Connect IQ overlay (#189): the app folded the
        // watch's day into the app-group snapshot, and the widget process —
        // which cannot see the overlay at all, it only talks to HealthKit —
        // must not overwrite it with a Santé that hasn't synced yet. Since #214
        // the floor itself travels in the snapshot, so the widget can compare
        // against it instead of against the merged total.
        let stored = snapshot(day: today, floorSteps: 4_200, floorMinutes: 25, floorDistanceKm: 3.1)
        let merged = stored.mergingLiveCounters(
            steps: 900, minutes: 4, distanceKm: 0.7, calories: 60, waterML: 750
        )
        #expect(merged.steps == 4_200)
        #expect(merged.minutes == 25)
        #expect(merged.distanceKm == 3.1)
        // …and never a sum.
        #expect(merged.steps != 5_100)
    }

    @Test("A live read that passes the stored value wins immediately")
    func liveReadWinsWhenHigher() {
        let stored = snapshot(day: today, floorSteps: 4_200, floorMinutes: 25, floorDistanceKm: 3.1)
        let merged = stored.mergingLiveCounters(
            steps: 11_000, minutes: 46, distanceKm: 8.4, calories: 500, waterML: 1_000
        )
        #expect(merged.steps == 11_000)
        #expect(merged.minutes == 46)
        #expect(merged.distanceKm == 8.4)
    }

    // MARK: - The floor, and only the floor (issue #214)

    @Test("With nothing lifted under it, a counter that falls is shown falling")
    func liveReadFallsWhenNothingFloorsIt() {
        // The #214 regression, and the case of every user without a Garmin
        // watch and no walk in flight: the stored 5.25 km is HealthKit's own,
        // from a walk since deleted in Santé, and the snapshot says so — a
        // recorded floor of zero. Flooring the live read against the stored
        // *total* pinned the widget at the day's high until the app republished.
        let stored = WidgetSnapshot(
            steps: 7_400, stepsGoal: 6_000, minutes: 38, minutesGoal: 20,
            distanceKm: 5.25, calories: 260, streak: 7, day: today,
            floorSteps: 0, floorMinutes: 0, floorDistanceKm: 0
        )
        let merged = stored.mergingLiveCounters(
            steps: 4_100, minutes: 19, distanceKm: 3.125, calories: 150, waterML: 500
        )
        #expect(merged.distanceKm == 3.125)
        #expect(merged.steps == 4_100)
        #expect(merged.minutes == 19)
    }

    @Test("The floor carries the post-walk overlay too, not just the watch's day")
    func postWalkFloorSurvivesALaggingRead() {
        // The other counter the widget process cannot measure (#158): the
        // iPhone takes up to a minute to flush a finished walk into HealthKit,
        // and `publishToWidgets` reloads the timelines immediately — so the
        // widget's own read is *guaranteed* to be below what the app just
        // published. Only steps and distance: the walk overlay never fakes
        // exercise minutes, so a minutes floor of 0 is the honest answer.
        let stored = WidgetSnapshot(
            steps: 4_200, stepsGoal: 6_000, minutes: 12, minutesGoal: 20,
            distanceKm: 3.0, calories: 90, streak: 7, day: today,
            floorSteps: 4_200, floorMinutes: 0, floorDistanceKm: 3.0
        )
        let merged = stored.mergingLiveCounters(
            steps: 3_000, minutes: 12, distanceKm: 2.0, calories: 90, waterML: 0
        )
        #expect(merged.steps == 4_200)
        #expect(merged.distanceKm == 3.0)
        // …and never a sum of the walk and the total it is already inside.
        #expect(merged.steps != 7_200)
    }

    @Test("A standing Garmin floor still holds the counters up over a silent Santé")
    func garminFloorHoldsCountersOverAZeroRead() {
        // #189's guarantee, the one that must survive: a Garmin-only user whose
        // Connect hasn't synced today. HealthKit answers, and answers zero.
        let stored = WidgetSnapshot(
            steps: 5_000, stepsGoal: 6_000, minutes: 30, minutesGoal: 20,
            distanceKm: 4.5, calories: 0, streak: 7, day: today,
            floorSteps: 5_000, floorMinutes: 30, floorDistanceKm: 4.5
        )
        let merged = stored.mergingLiveCounters(
            steps: 0, minutes: 0, distanceKm: 0, calories: 0, waterML: 0
        )
        #expect(merged.steps == 5_000)
        #expect(merged.minutes == 30)
        #expect(merged.distanceKm == 4.5)
    }

    @Test("HealthKit above the floor wins — the floor never latches")
    func healthKitAboveTheFloorWins() {
        let stored = WidgetSnapshot(
            steps: 5_000, stepsGoal: 6_000, minutes: 30, minutesGoal: 20,
            distanceKm: 4.5, calories: 0, streak: 7, day: today,
            floorSteps: 5_000, floorMinutes: 30, floorDistanceKm: 4.5
        )
        let merged = stored.mergingLiveCounters(
            steps: 6_000, minutes: 35, distanceKm: 4.75, calories: 300, waterML: 0
        )
        #expect(merged.steps == 6_000)
        #expect(merged.minutes == 35)
        #expect(merged.distanceKm == 4.75)
        // Never a sum, in either direction.
        #expect(merged.steps != 11_000)
    }

    @Test("Minutes merge through ActiveMinutes, cap included")
    func minutesGoThroughActiveMinutes() {
        // The minutes leg is not a bare `max`: it is `ActiveMinutes.merged`,
        // which also clamps to the number of minutes a day actually has.
        let stored = WidgetSnapshot(
            steps: 0, stepsGoal: 6_000, minutes: ActiveMinutes.dailyCap, minutesGoal: 20,
            distanceKm: 0, calories: 0, streak: 7, day: today,
            floorMinutes: 5_000
        )
        let merged = stored.mergingLiveCounters(
            steps: nil, minutes: 30, distanceKm: nil, calories: nil, waterML: nil
        )
        #expect(merged.minutes == ActiveMinutes.dailyCap)
    }

    @Test("A refused read keeps the stored counters even with a floor standing")
    func refusedReadKeepsStoredCountersWithAFloor() {
        // The floor decides what a live read may *not* drop below; it never
        // replaces a stored value on a leg nobody read. The app's total can sit
        // above its own floor (HealthKit had already passed it), and a locked
        // phone must keep that total, not fall back to the floor.
        let stored = snapshot(day: today, floorSteps: 1_000, floorMinutes: 5, floorDistanceKm: 0.5)
        let merged = stored.mergingLiveCounters(
            steps: nil, minutes: nil, distanceKm: nil, calories: nil, waterML: nil
        )
        #expect(merged.steps == 4_200)
        #expect(merged.minutes == 25)
        #expect(merged.distanceKm == 3.1)
    }

    @Test("A floor stamped yesterday cannot hold up today's counters")
    func yesterdaysFloorIsGoneByMorning() throws {
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        let merged = snapshot(day: yesterday, floorSteps: 14_000, floorMinutes: 90, floorDistanceKm: 9.5)
            .zeroedIfStale(today: today)
            .mergingLiveCounters(steps: 900, minutes: 4, distanceKm: 0.75, calories: 60, waterML: 0)
        #expect(merged.steps == 900)
        #expect(merged.minutes == 4)
        #expect(merged.distanceKm == 0.75)
    }

    @Test("Calories and water follow the live read, up or down")
    func caloriesAndWaterAreNotFloored() {
        // No overlay ever raises these two, and a deleted glass has to be able
        // to bring the water ring back down.
        let merged = snapshot(day: today).mergingLiveCounters(
            steps: nil, minutes: nil, distanceKm: nil, calories: 60, waterML: 250
        )
        #expect(merged.calories == 60)
        #expect(merged.waterML == 250)
    }

    @Test("A refused read (locked phone) keeps every stored counter")
    func refusedReadKeepsStoredCounters() {
        let merged = snapshot(day: today).mergingLiveCounters(
            steps: nil, minutes: nil, distanceKm: nil, calories: nil, waterML: nil
        )
        #expect(merged.steps == 4_200)
        #expect(merged.minutes == 25)
        #expect(merged.distanceKm == 3.1)
        #expect(merged.calories == 180)
        #expect(merged.waterML == 750)
    }

    @Test("Yesterday's totals are never the floor: zero first, then merge")
    func staleSnapshotContributesNoFloor() throws {
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        let merged = snapshot(day: yesterday)
            .zeroedIfStale(today: today)
            .mergingLiveCounters(steps: 900, minutes: 4, distanceKm: 0.7, calories: 60, waterML: 0)
        #expect(merged.steps == 900)
        #expect(merged.minutes == 4)
        #expect(merged.distanceKm == 0.7)
    }

    @Test("Snapshots written before the day stamp existed still decode")
    func tolerantDecodingWithoutDay() throws {
        let json = """
        {"steps":1200,"stepsGoal":6000,"minutes":8,"minutesGoal":20,\
        "distanceKm":0.9,"calories":55,"streak":3}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(decoded.steps == 1_200)
        #expect(decoded.streak == 3)
        #expect(decoded.day == nil)
    }

    @Test("A snapshot from before #214 still decodes, and keeps the pre-#214 rule")
    func tolerantDecodingWithoutTheRecordedFloor() throws {
        // Written by hand, not round-tripped through today's type: the payload
        // a build shipped before #214 left in the app group has no `floor*` key
        // at all, and the widget that reads it right after the update must
        // neither crash nor guess.
        //
        // The guess that matters is the unsafe one. This snapshot belongs to a
        // Garmin user whose Connect hasn't synced today: its 9 000 steps are
        // the watch's, the floor that justified them is still in the app's own
        // `UserDefaults.standard` where this process cannot reach it, and
        // HealthKit answers a real 0. Reading the missing key as "no floor"
        // would blank the Lock Screen ring for someone who walked 7 km — the
        // exact #189 symptom — for the one render before the app or a
        // background wake republishes. So absence means "unrecorded", and this
        // snapshot keeps the rule it was written under: max against the total.
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        let json = """
        {"steps":9000,"stepsGoal":6000,"minutes":44,"minutesGoal":20,\
        "distanceKm":7.0,"calories":260,"streak":3,"waterML":500,\
        "waterGoalML":2000,"hydrationEnabled":true,"hydrationGlassML":250,\
        "day":\(day)}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(decoded.floorSteps == nil)
        #expect(decoded.floorMinutes == nil)
        #expect(decoded.floorDistanceKm == nil)
        let merged = decoded.zeroedIfStale(today: today).mergingLiveCounters(
            steps: 0, minutes: 0, distanceKm: 0, calories: 0, waterML: 0
        )
        #expect(merged.steps == 9_000)
        #expect(merged.minutes == 44)
        #expect(merged.distanceKm == 7.0)
    }

    @Test("A recorded floor of zero is not the same as no record at all")
    func recordedZeroFloorLetsCountersFall() throws {
        // The counterpart, and why the two cases need distinct encodings: the
        // same totals, the same live 0, but written by a build that *did* look
        // and found nothing lifted. Here the fall is real and must show.
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        let json = """
        {"steps":9000,"stepsGoal":6000,"minutes":44,"minutesGoal":20,\
        "distanceKm":7.0,"calories":260,"streak":3,"waterML":500,\
        "waterGoalML":2000,"hydrationEnabled":true,"hydrationGlassML":250,\
        "day":\(day),"floorSteps":0,"floorMinutes":0,"floorDistanceKm":0}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(decoded.floorSteps == 0)
        let merged = decoded.zeroedIfStale(today: today).mergingLiveCounters(
            steps: 0, minutes: 0, distanceKm: 0, calories: 0, waterML: 0
        )
        #expect(merged.steps == 0)
        #expect(merged.minutes == 0)
        #expect(merged.distanceKm == 0)
    }

    @Test("A snapshot with no floor recorded is written without the keys")
    func encodingOmitsAnUnrecordedFloor() throws {
        // The wire format an older build has to keep reading: `encodeIfPresent`
        // on the three Optionals, so a pre-#214 decoder sees the payload it
        // always saw. Only checked for the nil case — a recorded floor is a new
        // key an old decoder ignores.
        let data = try JSONEncoder().encode(snapshot(day: today))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("floor"))
    }
}
