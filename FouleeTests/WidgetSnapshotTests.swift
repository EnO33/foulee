import Foundation
import Testing
@testable import Foulee

@Suite("WidgetSnapshot")
struct WidgetSnapshotTests {
    private let today = Calendar.current.startOfDay(for: .now)

    private func snapshot(day: Date?) -> WidgetSnapshot {
        WidgetSnapshot(
            steps: 4_200, stepsGoal: 6_000, minutes: 25, minutesGoal: 20,
            distanceKm: 3.1, calories: 180, streak: 7,
            waterML: 750, waterGoalML: 1_500, hydrationEnabled: true,
            day: day
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
        let zeroed = snapshot(day: yesterday).zeroedIfStale(today: today)
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
        // must not overwrite it with a Santé that hasn't synced yet.
        let stored = snapshot(day: today)
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
        let merged = snapshot(day: today).mergingLiveCounters(
            steps: 11_000, minutes: 46, distanceKm: 8.4, calories: 500, waterML: 1_000
        )
        #expect(merged.steps == 11_000)
        #expect(merged.minutes == 46)
        #expect(merged.distanceKm == 8.4)
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
}
