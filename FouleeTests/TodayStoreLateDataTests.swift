import Dependencies
import Foundation
import Testing
@testable import Foulee

/// Late-arriving data (issue #182). Garmin Connect flushes into Santé in
/// bursts — minutes to sometimes ~24 h late — so a day can read 0 at one
/// refresh and only receive its minutes the next day. Retroactive repair is
/// true by construction (#177 recomputes the streak over ~12 months on every
/// refresh, #193 credits workout minutes), and these tests pin it: no day
/// verdict may survive the data that revises it, **in either direction** —
/// a "streak never goes down" latch would be just as wrong as a missed repair,
/// since deleting a duplicate Garmin session in Santé must be able to shorten
/// a run.
///
/// **Boundary of this guarantee.** Repair happens on `TodayStore.refresh()`.
/// The HealthKit background wake (`refreshSnapshotMetrics`) only re-reads
/// today's counters and carries `snapshot.streak` forward, so a widget or a
/// complication can show a pre-repair streak until the app next comes to the
/// foreground — filed as issue #194, deliberately out of scope here.
///
/// **Freshness UX (#182 work item 3) — audited, not addressed.** `FreshnessStamp`
/// renders `Text(fetchedAt, style: .relative)` where `fetchedAt` is the instant
/// the *widget timeline* was built, not the instant Santé last received data.
/// For a Garmin user whose last burst landed yesterday, the stamp still reads
/// "MAJ 3 min" over stale-zeroed counters — honest about the render, silent
/// about the data. Fixing it needs a "data as of" instant on `WidgetSnapshot`
/// (which today only carries a day-granularity `day` stamp) plus the "Ouvre
/// Garmin Connect pour synchroniser" hint — both UI work owned by #185, so this
/// tests-only branch records the finding rather than acting on it.
@Suite("TodayStore late-arriving data")
struct TodayStoreLateDataTests {
    @Test("Yesterday's late minutes repair a streak already extended by today")
    @MainActor
    func lateYesterdayRepairsStreakAfterTodaysWalk() async throws {
        // J-10…J-2 walked, today walked, J-1 still empty: Garmin hasn't
        // flushed it yet, so the streak reads as "today only".
        let history = LockedRef(StreakTestSupport.walkedDays([0] + Array(2...10)))
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = StreakTestSupport.windowed { history.value }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.streak == 1)
            #expect(store.snapshot?.bestStreak == 9)

            // The burst lands the next day and fills J-1 retroactively.
            history.set(StreakTestSupport.walkedDays(Array(0...10)))
            await store.refresh()
            #expect(store.snapshot?.streak == 11)
            #expect(store.snapshot?.bestStreak == 11)
        }
    }

    @Test("The streak repairs even before today's own walk is recorded")
    @MainActor
    func lateYesterdayRepairsStreakBeforeTodaysWalk() async throws {
        // Nothing today yet — the streak is read from J-1 backwards, and J-1
        // is the day Garmin hasn't synced.
        let history = LockedRef(StreakTestSupport.walkedDays(Array(2...10)))
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = StreakTestSupport.windowed { history.value }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.streak == 0)

            history.set(StreakTestSupport.walkedDays(Array(1...10)))
            await store.refresh()
            #expect(store.snapshot?.streak == 10)
            #expect(store.snapshot?.bestStreak == 10)
        }
    }

    @Test("A day repaired deep in the history repairs the record too")
    @MainActor
    func lateMinutesRepairARecordRun() async throws {
        // Two 10-day runs separated by a single unsynced day at J-11.
        let history = LockedRef(StreakTestSupport.walkedDays(Array(0...10) + Array(12...21)))
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = StreakTestSupport.windowed { history.value }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.streak == 11)
            #expect(store.snapshot?.bestStreak == 11)

            // The hole fills in weeks later: the two runs become one.
            history.set(StreakTestSupport.walkedDays(Array(0...21)))
            await store.refresh()
            #expect(store.snapshot?.streak == 22)
            #expect(store.snapshot?.bestStreak == 22)
        }
    }

    @Test("A day that disappears from Santé shortens the streak — no upward latch")
    @MainActor
    func deletedDayShortensStreak() async throws {
        // Mirror image of the repair above: the same 11-day run, then J-3 goes
        // away (a duplicate Garmin session deleted in Santé, or a workout
        // re-attributed to another day). A `max(stored, computed)` latch would
        // keep showing 11 here.
        let history = LockedRef(StreakTestSupport.walkedDays(Array(0...10)))
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = StreakTestSupport.windowed { history.value }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.streak == 11)
            #expect(store.snapshot?.bestStreak == 11)

            history.set(StreakTestSupport.walkedDays([0, 1, 2] + Array(4...10)))
            await store.refresh()
            // Today, J-1 and J-2 survive; the record falls back to the
            // seven-day run that now sits before the hole.
            #expect(store.snapshot?.streak == 3)
            #expect(store.snapshot?.bestStreak == 7)
        }
    }
}

/// Today's own verdict is derived on every refresh, never latched — a Garmin
/// burst landing at 22:00 must be able to close the ring, and samples the user
/// deletes in Santé must be able to re-open it. The hero card (ring centre,
/// "Marche terminée" chip, "Marcher encore") reads `hasWalkedToday` straight
/// from the snapshot, so it follows both ways; `CelebrationBurst` is bound to
/// the end-of-walk screen, not to this flag, so it can't re-fire on a refresh.
@Suite("TodayStore day verdict revisability")
struct TodayVerdictRevisabilityTests {
    @Test("hasWalkedToday flips true when today's minutes land late")
    @MainActor
    func verdictFlipsWhenLateMinutesLand() async {
        let metrics = LockedRef(
            HealthMetrics(steps: 3_100, distanceKm: 2.1, activeMinutes: 4, activeCalories: 45)
        )
        await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.todayMetrics = { metrics.value }
        } operation: {
            let store = TodayStore()
            await store.refresh()
            #expect(store.snapshot?.hasWalkedToday == false)

            metrics.set(HealthMetrics(steps: 6_400, distanceKm: 4.6, activeMinutes: 28, activeCalories: 190))
            await store.refresh()
            #expect(store.snapshot?.hasWalkedToday == true)
            #expect(store.snapshot?.minutes == 28)
        }
    }

    @Test("hasWalkedToday flips back when the samples behind it disappear")
    @MainActor
    func verdictFollowsDownwardRevisions() async {
        // A duplicate Garmin session removed in Santé, or a workout re-attributed
        // to another day: the verdict must not stay pinned on "fait".
        let metrics = LockedRef(
            HealthMetrics(steps: 6_400, distanceKm: 4.6, activeMinutes: 28, activeCalories: 190)
        )
        await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.todayMetrics = { metrics.value }
        } operation: {
            let store = TodayStore()
            await store.refresh()
            #expect(store.snapshot?.hasWalkedToday == true)

            metrics.set(HealthMetrics(steps: 3_100, distanceKm: 2.1, activeMinutes: 4, activeCalories: 45))
            await store.refresh()
            #expect(store.snapshot?.hasWalkedToday == false)
        }
    }
}

/// The calendar sheet re-derives every cell from a freshly fetched history on
/// each `load()`, so a late burst repairs the ring the same way it repairs the
/// home card.
@Suite("Streak calendar late repair")
struct StreakCalendarLateDataTests {
    @Test("Yesterday's cell flips from missed to done when its minutes land late")
    @MainActor
    func yesterdayCellRepairs() async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let history = LockedRef<[DailyMinutes]>([])
        await withDependencies {
            $0.healthKit.dailyMinutes = { _ in history.value }
        } operation: {
            let store = StreakCalendarStore(
                goalMinutes: 20,
                goalSteps: 6_000,
                activeDays: Set(Weekday.allCases)
            )
            await store.load()
            #expect(Self.cell(for: yesterday, in: store)?.status == .missed)
            #expect(store.currentStreak == 0)

            history.set([DailyMinutes(date: yesterday, minutes: 25)])
            await store.load()
            let repaired = Self.cell(for: yesterday, in: store)
            #expect(repaired?.status == .done)
            #expect(repaired?.minutes == 25)
            #expect(store.currentStreak == 1)
        }
    }

    @MainActor
    private static func cell(for day: Date, in store: StreakCalendarStore) -> CalendarDay? {
        store.months
            .flatMap { month in month.cells.compactMap { $0 } }
            .first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
}

/// A sample that belongs to J-1 but is delivered on J must credit J-1 — the
/// mirror image of the repair: today's counters may never inherit a past day.
@Suite("Late samples keep their own day")
struct LateSampleDayAttributionTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let anchor = Date(timeIntervalSince1970: 1_716_768_000) // 2024-05-27

    @Test("A workout from yesterday delivered today credits yesterday, not today")
    func yesterdayWorkoutCreditsYesterday() throws {
        let today = calendar.startOfDay(for: anchor)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let burst = [
            ActiveMinutes.WorkoutInterval(
                start: yesterday.addingTimeInterval(12 * 3_600),
                duration: 25 * 60
            )
        ]
        let byDay = ActiveMinutes.workoutMinutesByDay(burst, calendar: calendar)
        #expect(byDay[yesterday] == 25)
        #expect(byDay[today] == nil)
        // Today's merged value stays at whatever today really produced.
        #expect(ActiveMinutes.merged(appleMinutes: 0, workoutMinutes: byDay[today] ?? 0) == 0)
    }
}
