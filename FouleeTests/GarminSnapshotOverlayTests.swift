import Foundation
import Testing
@testable import Foulee

/// The Connect IQ merge (issue #189), pinned hard: it is the one place where a
/// Garmin day can silently be counted twice, replaced by a stale aggregate, or
/// resurrected the morning after.
///
/// Every case runs against a fixed `now` (local noon today) so the day-stamp
/// assertions can't flake near midnight, and the merge takes `now` as a
/// parameter precisely so they can.
@Suite("Garmin Connect IQ overlay")
struct GarminSnapshotOverlayTests {
    private let calendar = Calendar.current

    /// Local noon today — far from both midnight boundaries.
    private var now: Date { calendar.startOfDay(for: .now).addingTimeInterval(12 * 60 * 60) }

    /// A watch snapshot assembled `minutesAgo` before `now`, or on another day
    /// when `daysAgo` is given.
    private func snapshot(
        steps: Int = 0,
        distanceCm: Int = 0,
        activeMinutes: Int = 0,
        vigorous: Int = 0,
        calories: Int = 0,
        minutesAgo: Double = 3,
        daysAgo: Int = 0,
        generation: Int = 1
    ) -> GarminDailySnapshot {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return GarminDailySnapshot(
            steps: steps,
            distanceCm: distanceCm,
            activeMinutes: activeMinutes,
            activeMinutesVigorous: vigorous,
            calories: calories,
            timestamp: day.addingTimeInterval(-minutesAgo * 60),
            generation: generation
        )
    }

    private func healthKit(
        steps: Int = 0,
        distanceKm: Double = 0,
        activeMinutes: Int = 0,
        activeCalories: Int = 0
    ) -> HealthMetrics {
        HealthMetrics(
            steps: steps,
            distanceKm: distanceKm,
            activeMinutes: activeMinutes,
            activeCalories: activeCalories
        )
    }

    /// The whole path a snapshot takes on a refresh: freshness gate, then the
    /// merge — one clock for both.
    private func merged(_ metrics: HealthMetrics, _ ciq: GarminDailySnapshot?) -> HealthMetrics {
        GarminSnapshotOverlay.merged(
            healthKit: metrics,
            overlay: GarminSnapshotOverlay.contribution(of: ciq, now: now, calendar: calendar)
        )
    }

    // MARK: - Never add

    @Test("Two channels describing the same day are maxed, never summed")
    func neverAdds() {
        // The recurring nightmare: 4 000 steps in Santé (Garmin Connect synced
        // this morning) plus a 4 200 watch snapshot is *one* day of 4 200 steps.
        let result = merged(healthKit(steps: 4_000), snapshot(steps: 4_200))
        #expect(result.steps == 4_200)
        #expect(result.steps != 8_200)
    }

    @Test("Active minutes are a third term of the same max, not a third addend")
    func minutesNeverAdd() {
        // 30 HealthKit minutes (Garmin's workout, already merged with Apple's
        // exercise time) and a 30-minute watch total are the same 30 minutes.
        let result = merged(healthKit(activeMinutes: 30), snapshot(activeMinutes: 30))
        #expect(result.activeMinutes == 30)
    }

    @Test("Distance is maxed, never summed")
    func distanceNeverAdds() {
        // 631 500 cm = 6.315 km against 6.0 km already in Santé.
        let result = merged(healthKit(distanceKm: 6.0), snapshot(distanceCm: 631_500))
        #expect(result.distanceKm == 6.315)
    }

    // MARK: - Freshness beats HealthKit, HealthKit catches up

    @Test("A fresher, higher snapshot shows — and yields the moment Santé passes it")
    func freshSnapshotWinsThenYields() {
        let watch = snapshot(steps: 9_000, distanceCm: 700_000, activeMinutes: 40)

        // Garmin Connect hasn't synced the afternoon yet: the watch total wins.
        let early = merged(healthKit(steps: 3_000, distanceKm: 2.4, activeMinutes: 12), watch)
        #expect(early.steps == 9_000)
        #expect(early.distanceKm == 7.0)
        #expect(early.activeMinutes == 40)

        // Garmin Connect syncs and lands higher than the watch's last push.
        // No latch: HealthKit takes the display back on the same snapshot.
        let late = merged(healthKit(steps: 11_200, distanceKm: 8.9, activeMinutes: 55), watch)
        #expect(late.steps == 11_200)
        #expect(late.distanceKm == 8.9)
        #expect(late.activeMinutes == 55)
    }

    // MARK: - Day stamp (the bug that bit #144, #152, #203)

    @Test("A snapshot from yesterday contributes nothing to today")
    func yesterdayContributesNothing() {
        let yesterday = snapshot(steps: 14_000, distanceCm: 900_000, activeMinutes: 90, daysAgo: 1)
        #expect(GarminSnapshotOverlay.contribution(of: yesterday, now: now, calendar: calendar) == nil)

        let result = merged(healthKit(steps: 300, distanceKm: 0.2, activeMinutes: 1), yesterday)
        #expect(result.steps == 300)
        #expect(result.distanceKm == 0.2)
        #expect(result.activeMinutes == 1)
    }

    @Test("Recent is not the same question as today")
    func recentButPreviousDayIsStillAnotherDay() {
        // 00:10, with a snapshot assembled at 23:50 the night before: twenty
        // minutes old, well inside the freshness horizon — and describing a day
        // that is over. The day stamp is what catches it.
        let justAfterMidnight = calendar.startOfDay(for: now).addingTimeInterval(10 * 60)
        let lastNight = GarminDailySnapshot(
            steps: 12_000, distanceCm: 800_000, activeMinutes: 60, activeMinutesVigorous: 0,
            calories: 0, timestamp: justAfterMidnight.addingTimeInterval(-20 * 60), generation: 4
        )
        #expect(GarminSnapshotOverlay.usability(lastNight, now: justAfterMidnight, calendar: calendar) == .otherDay)
        let result = GarminSnapshotOverlay.merged(
            healthKit: healthKit(steps: 40),
            overlay: GarminSnapshotOverlay.contribution(of: lastNight, now: justAfterMidnight, calendar: calendar)
        )
        #expect(result.steps == 40)
    }

    // MARK: - Freshness horizon

    @Test("The freshness horizon is a relation to the sync hint, not a literal")
    func horizonIsHalfOfStaleAfter() {
        // The overlay must stop taking new totals well before the app itself
        // tells the user their Garmin day is behind — a literal here could
        // silently drift past `staleAfter` when that one is tuned.
        #expect(GarminSnapshotOverlay.freshnessHorizon == GarminFreshness.staleAfter / 2)
        #expect(GarminSnapshotOverlay.freshnessHorizon < GarminFreshness.staleAfter)
    }

    @Test("A same-day snapshot past the freshness horizon can no longer raise the overlay")
    func staleSameDaySnapshotIsIgnored() {
        let horizonMinutes = GarminSnapshotOverlay.freshnessHorizon / 60
        let justInside = snapshot(steps: 9_000, minutesAgo: horizonMinutes - 1)
        let justOutside = snapshot(steps: 9_000, minutesAgo: horizonMinutes + 1)
        #expect(merged(healthKit(steps: 2_000), justInside).steps == 9_000)
        #expect(merged(healthKit(steps: 2_000), justOutside).steps == 2_000)
        #expect(GarminSnapshotOverlay.usability(justOutside, now: now, calendar: calendar) == .tooOld)
    }

    @Test("A watch clock a little ahead is tolerated, a wild one is not — and says so")
    func clockSkew() {
        let skewMinutes = GarminSnapshotOverlay.clockSkewTolerance / 60
        let slightlyAhead = snapshot(steps: 5_000, minutesAgo: -(skewMinutes - 1))
        let wayAhead = snapshot(steps: 5_000, minutesAgo: -(skewMinutes + 60))
        #expect(merged(healthKit(steps: 100), slightlyAhead).steps == 5_000)
        #expect(merged(healthKit(steps: 100), wayAhead).steps == 100)
        // A watch clock set wrong refuses every snapshot forever, and this
        // target logs nothing: the reason has to be readable somewhere.
        #expect(GarminSnapshotOverlay.usability(wayAhead, now: now, calendar: calendar) == .clockAhead)
    }

    // MARK: - The high-water floor

    @Test("The floor keeps the day's best contribution, per metric")
    func floorRises() {
        let morning = GarminSnapshotOverlay.Contribution(steps: 4_000, distanceKm: 3.0, activeMinutes: 20)
        let afternoon = GarminSnapshotOverlay.Contribution(steps: 9_000, distanceKm: 7.1, activeMinutes: 41)
        let raised = GarminSnapshotOverlay.raised(
            GarminSnapshotOverlay.raised(nil, with: morning, now: now, calendar: calendar),
            with: afternoon, now: now, calendar: calendar
        )
        #expect(raised.contribution == afternoon)
        // …and a later snapshot that reports *less* can't pull the day back.
        let dip = GarminSnapshotOverlay.raised(raised, with: morning, now: now, calendar: calendar)
        #expect(dip.contribution == afternoon)
    }

    @Test("A floor from another day is replaced, never raised")
    func floorFromAnotherDayIsReplaced() {
        let yesterdayNoon = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterday = GarminSnapshotOverlay.raised(
            nil,
            with: GarminSnapshotOverlay.Contribution(steps: 14_000, distanceKm: 9.9, activeMinutes: 90),
            now: yesterdayNoon, calendar: calendar
        )
        #expect(GarminSnapshotOverlay.standing(yesterday, now: now, calendar: calendar) == nil)

        let today = GarminSnapshotOverlay.Contribution(steps: 300, distanceKm: 0.2, activeMinutes: 1)
        let raised = GarminSnapshotOverlay.raised(yesterday, with: today, now: now, calendar: calendar)
        #expect(raised.contribution == today)
    }

    // MARK: - Apple data wins when present

    @Test("A hybrid user's Apple Watch numbers are never replaced by the watch aggregate")
    func appleWinsWhenHigher() {
        // `HealthMetrics.activeMinutes` already carries max(appleExerciseTime,
        // workout minutes). A Garmin snapshot that is lower must not pull it
        // down, and one that is higher must not double it.
        let apple = healthKit(steps: 12_400, distanceKm: 9.1, activeMinutes: 52, activeCalories: 430)
        let garmin = snapshot(steps: 8_000, distanceCm: 600_000, activeMinutes: 35)
        let result = merged(apple, garmin)
        #expect(result.steps == 12_400)
        #expect(result.distanceKm == 9.1)
        #expect(result.activeMinutes == 52)
        #expect(result.activeCalories == 430)
    }

    // MARK: - Garmin's doubled vigorous minutes

    @Test("Vigorous minutes are not counted twice against appleExerciseTime")
    func vigorousMinutesAreUndoubled() {
        // Garmin's total is moderate + 2 × vigorous. A 20-minute walk plus a
        // 20-minute run reads as 60 there, but is 40 minutes of wall clock —
        // which is what `appleExerciseTime` measures.
        let intense = snapshot(activeMinutes: 60, vigorous: 20)
        #expect(GarminSnapshotOverlay.wallClockActiveMinutes(intense) == 40)
        #expect(merged(healthKit(activeMinutes: 0), intense).activeMinutes == 40)
    }

    @Test("A family reporting no vigorous share keeps its total")
    func noVigorousShare() {
        #expect(GarminSnapshotOverlay.wallClockActiveMinutes(snapshot(activeMinutes: 25)) == 25)
    }

    @Test("An incoherent vigorous share under-credits rather than inventing minutes")
    func incoherentVigorousShare() {
        #expect(GarminSnapshotOverlay.wallClockActiveMinutes(snapshot(activeMinutes: 10, vigorous: 40)) == 0)
    }

    @Test("Active minutes are capped at a day's worth")
    func minutesAreCapped() {
        let absurd = snapshot(activeMinutes: 100_000)
        #expect(merged(healthKit(activeMinutes: 30), absurd).activeMinutes == ActiveMinutes.dailyCap)
    }

    // MARK: - Calories

    @Test("Calories are never merged: Garmin's are a total burn, not an active one")
    func caloriesAreNeverMerged() {
        // Garmin's `Info.calories` includes basal metabolism. Maxing it against
        // activeEnergyBurned wouldn't double-count — it would simply show a
        // wrong number, ~2000 kcal where the user burned ~400 actively.
        let result = merged(healthKit(activeCalories: 400), snapshot(calories: 2_100))
        #expect(result.activeCalories == 400)
    }

    // MARK: - Missing, partial and absent snapshots

    @Test("No snapshot at all leaves HealthKit exactly as it was")
    func noSnapshotIsPassthrough() {
        let metrics = healthKit(steps: 7_000, distanceKm: 5.2, activeMinutes: 31, activeCalories: 260)
        #expect(merged(metrics, nil) == metrics)
    }

    @Test("A snapshot whose fields are all missing invents nothing")
    func emptySnapshotInventsNothing() {
        // The #187 decoder turns an absent or mistyped metric into 0, so a
        // watch build that predates a field lands here. Zeros must lose every
        // max rather than blank the day.
        let metrics = healthKit(steps: 7_000, distanceKm: 5.2, activeMinutes: 31, activeCalories: 260)
        #expect(merged(metrics, snapshot()) == metrics)
    }

    @Test("A snapshot filling only some fields contributes only those")
    func partialSnapshotContributesOnlyWhatItHas() {
        // Steps-only watch build: steps rise, everything else is untouched.
        let result = merged(healthKit(steps: 100, distanceKm: 5.2, activeMinutes: 31), snapshot(steps: 9_000))
        #expect(result.steps == 9_000)
        #expect(result.distanceKm == 5.2)
        #expect(result.activeMinutes == 31)
    }

    @Test("Negative values from a corrupt payload can never pull a total down")
    func negativeValuesCannotPullDown() {
        let corrupt = GarminDailySnapshot(
            steps: -500, distanceCm: -1_000, activeMinutes: -10, activeMinutesVigorous: 0,
            calories: 0, timestamp: now.addingTimeInterval(-60), generation: 1
        )
        let result = merged(healthKit(steps: 3_000, distanceKm: 2.1, activeMinutes: 15), corrupt)
        #expect(result.steps == 3_000)
        #expect(result.distanceKm == 2.1)
        #expect(result.activeMinutes == 15)
    }
}

/// Ingestion: which snapshots earn the overlay slot, and what survives a
/// relaunch. `UserDefaults` is a per-test suite so nothing races the app's own.
@Suite("Garmin Connect IQ ingestion")
struct GarminSnapshotIngestionTests {
    private let calendar = Calendar.current
    private var now: Date { calendar.startOfDay(for: .now).addingTimeInterval(12 * 60 * 60) }

    private func snapshot(
        steps: Int,
        minutesAgo: Double = 1,
        daysAgo: Int = 0,
        generation: Int
    ) -> GarminDailySnapshot {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return GarminDailySnapshot(
            steps: steps, distanceCm: 0, activeMinutes: 0, activeMinutesVigorous: 0,
            calories: 0, timestamp: day.addingTimeInterval(-minutesAgo * 60), generation: generation
        )
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "GarminSnapshotIngestionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func accept(
        _ snapshot: GarminDailySnapshot,
        _ defaults: UserDefaults
    ) -> GarminSnapshotIngestion.Outcome {
        GarminSnapshotIngestion.accept(snapshot, now: now, defaults: defaults, calendar: calendar)
    }

    @Test("A fresh snapshot becomes the overlay and survives a relaunch")
    func freshSnapshotIsStored() throws {
        try withDefaults { defaults in
            #expect(accept(snapshot(steps: 6_100, generation: 3), defaults) == .accepted)
            let stored = GarminSnapshotStore.read(now: now, from: defaults, calendar: calendar)
            #expect(stored?.steps == 6_100)
            #expect(GarminSnapshotStore.readFloor(now: now, from: defaults, calendar: calendar)?.steps == 6_100)
        }
    }

    @Test("An older generation is dropped: BLE reorders and redelivers")
    func olderGenerationIsDropped() throws {
        try withDefaults { defaults in
            #expect(accept(snapshot(steps: 6_100, generation: 3), defaults) == .accepted)
            #expect(accept(snapshot(steps: 2_000, generation: 2), defaults) == .superseded)
            #expect(GarminSnapshotStore.read(now: now, from: defaults, calendar: calendar)?.steps == 6_100)
        }
    }

    @Test("A snapshot already stale on arrival never becomes the overlay")
    func staleOnArrivalIsRejected() throws {
        try withDefaults { defaults in
            let horizonMinutes = GarminSnapshotOverlay.freshnessHorizon / 60
            let stale = snapshot(steps: 9_000, minutesAgo: horizonMinutes + 30, generation: 9)
            #expect(accept(stale, defaults) == .tooOld)
            #expect(GarminSnapshotStore.read(now: now, from: defaults, calendar: calendar) == nil)
            #expect(GarminSnapshotStore.readFloor(now: now, from: defaults, calendar: calendar) == nil)
        }
    }

    @Test("A snapshot from yesterday never becomes the overlay")
    func yesterdayIsRejected() throws {
        try withDefaults { defaults in
            #expect(accept(snapshot(steps: 14_000, daysAgo: 1, generation: 12), defaults) == .otherDay)
            #expect(GarminSnapshotStore.read(now: now, from: defaults, calendar: calendar) == nil)
        }
    }

    @Test("A stored snapshot that expired reads as nothing, and stops blocking")
    func expiredStoredSnapshotStopsBlocking() throws {
        try withDefaults { defaults in
            // Yesterday's record, written before midnight, with a high
            // generation. It must neither be read today…
            let yesterday = snapshot(steps: 14_000, daysAgo: 1, generation: 40)
            GarminSnapshotStore.write(yesterday, to: defaults)
            #expect(GarminSnapshotStore.read(now: now, from: defaults, calendar: calendar) == nil)

            // …nor keep a today snapshot out because its counter is lower —
            // which is also how a watch-side counter reset recovers.
            #expect(accept(snapshot(steps: 800, generation: 1), defaults) == .accepted)
            #expect(GarminSnapshotStore.read(now: now, from: defaults, calendar: calendar)?.steps == 800)
        }
    }

    // MARK: - Why a snapshot was refused (no logger in this target)

    @Test("The last verdict is kept, so a wrong watch clock isn't silent")
    func lastOutcomeIsRecorded() throws {
        try withDefaults { defaults in
            // Every snapshot from a watch whose clock runs an hour fast is
            // refused, forever, and nothing is logged: the store is the only
            // place that can say why.
            let ahead = snapshot(steps: 5_000, minutesAgo: -60, generation: 2)
            #expect(accept(ahead, defaults) == .clockAhead)
            #expect(GarminSnapshotStore.lastOutcome(from: defaults) == .clockAhead)

            #expect(accept(snapshot(steps: 5_000, generation: 3), defaults) == .accepted)
            #expect(GarminSnapshotStore.lastOutcome(from: defaults) == .accepted)
        }
    }

    // MARK: - The floor: counters never count down (the horizon doesn't end it)

    @Test("The floor outlives the freshness horizon — within the day")
    func floorSurvivesHorizonExpiry() throws {
        try withDefaults { defaults in
            #expect(accept(snapshot(steps: 7_400, generation: 6), defaults) == .accepted)
            let later = now.addingTimeInterval(GarminSnapshotOverlay.freshnessHorizon + 60 * 60)

            // The record can no longer speak for the ordering — but the day's
            // counters must not fall back to a Santé that hasn't synced.
            #expect(GarminSnapshotStore.read(now: later, from: defaults, calendar: calendar) == nil)
            #expect(GarminSnapshotStore.readFloor(now: later, from: defaults, calendar: calendar)?.steps == 7_400)
        }
    }

    @Test("The floor dies at local midnight, like every other overlay here")
    func floorDiesAtMidnight() throws {
        try withDefaults { defaults in
            #expect(accept(snapshot(steps: 12_000, generation: 6), defaults) == .accepted)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            #expect(GarminSnapshotStore.readFloor(now: tomorrow, from: defaults, calendar: calendar) == nil)
        }
    }

    @Test("A fresher snapshot raises the floor; Santé passing it takes the display back")
    func floorRisesAndYieldsToHealthKit() throws {
        try withDefaults { defaults in
            #expect(accept(snapshot(steps: 4_000, generation: 1), defaults) == .accepted)
            #expect(accept(snapshot(steps: 9_500, generation: 2), defaults) == .accepted)
            let floor = GarminSnapshotStore.readFloor(now: now, from: defaults, calendar: calendar)
            #expect(floor?.steps == 9_500)

            // No latch: the merge takes the larger of the two every pass, so
            // Garmin Connect syncing higher wins on the spot.
            let metrics = HealthMetrics(steps: 11_200, distanceKm: 8.9, activeMinutes: 55, activeCalories: 500)
            #expect(GarminSnapshotOverlay.merged(healthKit: metrics, overlay: floor).steps == 11_200)
        }
    }

    // MARK: - Widget reload budget

    @Test("The watch's five-minute cadence can't buy a reload every five minutes")
    func reloadIsThrottled() {
        let throttle = GarminSnapshotIngestion.reloadThrottle
        #expect(throttle == TimeInterval(WidgetRefresh.daytimeStepMinutes * 60))

        // First accepted snapshot of the process: nothing spent yet.
        #expect(GarminSnapshotIngestion.shouldReloadWidgets(countersMoved: true, lastReloadAt: nil, now: now))
        // The watch transmits *because* its metrics moved, so "the counters
        // changed" is true on nearly every push — the throttle is what keeps
        // this channel inside the 40-70 reloads/day WidgetKit grants.
        #expect(!GarminSnapshotIngestion.shouldReloadWidgets(
            countersMoved: true, lastReloadAt: now.addingTimeInterval(-throttle + 60), now: now
        ))
        #expect(GarminSnapshotIngestion.shouldReloadWidgets(
            countersMoved: true, lastReloadAt: now.addingTimeInterval(-throttle), now: now
        ))
        // Nothing moved: never worth a reload, throttle or not.
        #expect(!GarminSnapshotIngestion.shouldReloadWidgets(countersMoved: false, lastReloadAt: nil, now: now))
    }

    @Test("A reload stamp in the future doesn't wedge the channel")
    func futureReloadStampIsIgnored() throws {
        try withDefaults { defaults in
            GarminSnapshotIngestion.markReloaded(at: now.addingTimeInterval(3 * 60 * 60), defaults: defaults)
            #expect(GarminSnapshotIngestion.lastReloadAt(defaults: defaults, now: now) == nil)

            GarminSnapshotIngestion.markReloaded(at: now.addingTimeInterval(-60), defaults: defaults)
            #expect(GarminSnapshotIngestion.lastReloadAt(defaults: defaults, now: now) != nil)
        }
    }
}
