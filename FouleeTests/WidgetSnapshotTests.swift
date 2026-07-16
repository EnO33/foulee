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
