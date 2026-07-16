import Foundation
import Testing
@testable import Foulee

@Suite struct WidgetTimelineBuilderTests {
    /// Fixed UTC calendar so the hour math is deterministic on any machine.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: hour, minute: minute))!
    }

    private func snapshot(
        steps: Int = 4_000, stepsGoal: Int = 6_000,
        minutes: Int = 15, minutesGoal: Int = 20
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            steps: steps, stepsGoal: stepsGoal, minutes: minutes, minutesGoal: minutesGoal,
            distanceKm: 2.8, calories: 180, streak: 3
        )
    }

    private func projected(
        _ snapshot: WidgetSnapshot, now: Date, nextRefresh: Date
    ) -> [WidgetProjectedValue] {
        WidgetTimelineBuilder.projectedValues(
            counters: snapshot.counters, now: now, nextRefresh: nextRefresh,
            nextMidnight: WidgetRefresh.nextMidnight(after: now, calendar: calendar),
            calendar: calendar
        )
    }

    @Test func firstValueIsTheUnprojectedNow() {
        let values = projected(snapshot(), now: date(10, 3), nextRefresh: date(10, 10))
        #expect(values.first == WidgetProjectedValue(
            date: date(10, 3), steps: 4_000, minutes: 15, distanceKm: 2.8, calories: 180
        ))
    }

    @Test func entriesComeEveryTwoMinutesStrictlyBeforeNextRefresh() {
        let values = projected(snapshot(), now: date(10, 3), nextRefresh: date(10, 10))
        #expect(values.map(\.date) == [date(10, 3), date(10, 5), date(10, 7), date(10, 9)])
    }

    @Test func valuesNeverDecrease() {
        // 3 000 steps by 06:40 → 75/min, an active pace: both counters move.
        let values = projected(snapshot(steps: 3_000), now: date(6, 40), nextRefresh: date(6, 50))
        for (previous, next) in zip(values, values.dropFirst()) {
            #expect(next.steps >= previous.steps)
            #expect(next.minutes >= previous.minutes)
        }
        #expect(values.last!.steps > values.first!.steps)
    }

    @Test func stepsAreCappedAtTwiceTheGoal() {
        // ~197 steps/min since 06:00 — the raw projection blows past 2× the
        // goal on the very first future entry.
        let values = projected(
            snapshot(steps: 5_900, stepsGoal: 3_000), now: date(6, 30), nextRefresh: date(6, 40)
        )
        #expect(values.allSatisfy { $0.steps <= 6_000 })
        #expect(values.last?.steps == 6_000)
    }

    @Test func stepsAlreadyBeyondTheCapStayFlatInsteadOfDecreasing() {
        let values = projected(
            snapshot(steps: 7_000, stepsGoal: 3_000), now: date(6, 30), nextRefresh: date(6, 40)
        )
        #expect(values.allSatisfy { $0.steps == 7_000 })
    }

    @Test func stepsGainIsCappedAtFifteenPercentOfTheGoal() {
        // 800/min burst pace with a huge goal: neither the goal clamp nor 2×
        // goal binds — the +15 % of goal (3 000) ceiling does: 4 000 → 7 000.
        let values = projected(
            snapshot(steps: 4_000, stepsGoal: 20_000), now: date(6, 5), nextRefresh: date(6, 15)
        )
        #expect(values.allSatisfy { $0.steps <= 7_000 })
        #expect(values.last?.steps == 7_000)
    }

    @Test func projectionNeverFabricatesAGoalCrossing() {
        // 5 800/6 000 at a 200/min pace: the raw projection crosses the goal
        // on the first future entry — the clamp must hold it at goal − 1.
        // A closed ring is a promise; only real steps may close it.
        let values = projected(
            snapshot(steps: 5_800, stepsGoal: 6_000), now: date(6, 29), nextRefresh: date(6, 39)
        )
        #expect(values.allSatisfy { $0.steps <= 5_999 })
        #expect(values.last?.steps == 5_999)
    }

    @Test func entriesStayFlatWhenTheNextReloadWontCorrectSoon() {
        // Last build of the day (next wake 08:00): a projection would sit on
        // screen for hours with nothing to correct it — entries are re-dated
        // but flat.
        let values = projected(
            snapshot(steps: 5_000),
            now: date(20, 2),
            nextRefresh: WidgetRefresh.nextRefresh(after: date(20, 2), calendar: calendar)
        )
        #expect(values.count > 1)
        #expect(values.allSatisfy { $0.steps == 5_000 })
        #expect(values.allSatisfy { $0.minutes == 15 })
    }

    @Test func noInterpolatedEntryCrossesMidnight() {
        let values = projected(
            snapshot(), now: date(23, 55),
            nextRefresh: WidgetRefresh.nextRefresh(after: date(23, 55), calendar: calendar)
        )
        let midnight = WidgetRefresh.nextMidnight(after: date(23, 55), calendar: calendar)
        #expect(values.map(\.date) == [date(23, 55), date(23, 57), date(23, 59)])
        #expect(values.allSatisfy { $0.date < midnight })
    }

    @Test func entryCountIsBoundedWhenTheNextRefreshIsFarAway() {
        // 20:30 → next refresh at 08:00 tomorrow: without a cap this would
        // mean 100+ entries before midnight alone.
        let values = projected(
            snapshot(), now: date(20, 30),
            nextRefresh: WidgetRefresh.nextRefresh(after: date(20, 30), calendar: calendar)
        )
        #expect(values.count == WidgetTimelineBuilder.maxProjectedEntries + 1)
        #expect(values.last?.date == date(21, 10))
    }

    @Test func minutesStayFlatAtAnIdlePace() {
        // 500 steps by noon (~1.4/min) — no evidence of ongoing activity, so
        // the exercise-minutes counter must not creep up.
        let values = projected(snapshot(steps: 500), now: date(12, 0), nextRefresh: date(12, 10))
        #expect(values.allSatisfy { $0.minutes == 15 })
    }

    @Test func minutesAdvanceAtMostOnePerElapsedMinuteWhileActive() {
        let values = projected(snapshot(steps: 3_000), now: date(6, 40), nextRefresh: date(6, 50))
        // +1 minute per elapsed minute — until the goal clamp (20) stops the
        // projection just short of a fabricated goal crossing.
        #expect(values.map(\.minutes) == [15, 17, 19, 19, 19])
    }

    @Test func minutesAreCappedAtTwiceTheGoal() {
        let values = projected(
            snapshot(steps: 3_000, minutes: 39, minutesGoal: 20), now: date(6, 40), nextRefresh: date(6, 50)
        )
        #expect(values.allSatisfy { $0.minutes <= 40 })
        #expect(values.last?.minutes == 40)
    }

    @Test func distanceAndCaloriesPassThroughFlat() {
        // Active pace, so steps/minutes do move — distance and calories must
        // still be carried through untouched (no fake projection).
        let values = projected(snapshot(steps: 3_000), now: date(6, 40), nextRefresh: date(6, 50))
        #expect(values.allSatisfy { $0.distanceKm == 2.8 })
        #expect(values.allSatisfy { $0.calories == 180 })
    }

    @Test func beforeTheRateWindowEverythingStaysFlat() {
        // 05:00: no minutes elapsed since 06:00 yet, so the rate floors at 0
        // and the projection is a flat re-dating, not extrapolation.
        let values = projected(snapshot(steps: 1_000), now: date(5, 0), nextRefresh: date(8, 0))
        #expect(values.count > 1)
        #expect(values.allSatisfy { $0.steps == 1_000 })
        #expect(values.allSatisfy { $0.minutes == 15 })
    }

    @Test func relevanceIsHigherInsideTheActivityWindow() {
        let daytime = WidgetTimelineBuilder.relevanceScore(at: date(12, 0), calendar: calendar)
        let night = WidgetTimelineBuilder.relevanceScore(at: date(23, 0), calendar: calendar)
        #expect(daytime == 1)
        #expect(daytime > night)
    }
}
