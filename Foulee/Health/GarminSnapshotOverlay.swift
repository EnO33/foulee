import Foundation

/// Arbitration between the two channels a Garmin day reaches Foulée by
/// (issue #189). Pure Foundation: the whole rule is testable without a watch,
/// a BLE link or HealthKit.
///
/// - **HealthKit**, written by Garmin Connect: late (syncs in bursts, sometimes
///   24 h behind), granular, authoritative, and already merged across sources
///   by `HKStatisticsQuery`.
/// - **The Connect IQ snapshot**, pushed by the watch app over BLE: fresh
///   (≤ 5 min while the watch is in range), but one aggregated daily total.
///
/// They describe the *same* underlying activity, so two rules hold, and neither
/// is negotiable:
///
/// 1. **Nothing here is ever written to HealthKit.** Garmin Connect will sync
///    the same day later; a sample written from this channel would sit next to
///    it forever and double-count the user's own Health data, with no way for
///    Foulée to take it back. The snapshot lives only as this local overlay —
///    the same shape as the post-walk `PendingWalk` overlay.
/// 2. **Channels are never added — per metric, per day, a `max`.** Garmin's
///    intensity minutes and the workouts Garmin Connect writes into Santé are
///    usually the very same activity; summing them would invent minutes the
///    clock never had. `max` also settles the hybrid Apple Watch + Garmin user
///    for free: `appleExerciseTime` is already inside the HealthKit term, so a
///    stale Garmin aggregate can never replace an Apple number that is higher.
/// 3. **Counters never count down.** What the watch measured stays as a
///    day-stamped high-water floor until local midnight, even once the
///    snapshot behind it is too old to be replaced — see `Floor`.
///
/// The overlay feeds the **displayed counters** only. The streak keeps reading
/// its history from HealthKit (`mergedDailyMinutes`): a streak resting on a
/// two-hour overlay would appear and vanish with BLE range.
enum GarminSnapshotOverlay {
    /// Past this age a snapshot no longer earns the day's overlay.
    ///
    /// The watch pushes every five minutes while the phone is in range, and
    /// only when its own metrics moved — so an hour of silence already means
    /// out of range or genuinely idle. Half of `GarminFreshness.staleAfter`,
    /// written as that relation rather than as its own literal: the overlay
    /// must stop accepting new totals well before the app itself starts
    /// telling the user their Garmin day is behind, and the two constants have
    /// to move together.
    static let freshnessHorizon: TimeInterval = GarminFreshness.staleAfter / 2

    /// A watch clock a few minutes ahead of the phone's is normal, and would
    /// otherwise make every snapshot arrive "from the future" and be dropped.
    static let clockSkewTolerance: TimeInterval = 5 * 60

    /// What a usable snapshot contributes to today. Calories are absent by
    /// design — see `merged(healthKit:overlay:)`.
    ///
    /// `Codable` because the day's contribution is persisted as a floor (see
    /// `Floor`), not just held for the length of one refresh.
    struct Contribution: Codable, Equatable, Sendable {
        var steps: Int
        var distanceKm: Double
        var activeMinutes: Int
    }

    /// **The high-water floor: the rule that keeps counters from counting
    /// down.** The day's best contribution so far, stamped with the local day
    /// it was earned on.
    ///
    /// Without it the overlay simply vanishes once `freshnessHorizon` passes,
    /// and app, app group and widgets all republish HealthKit-only totals —
    /// often 0 for a Garmin-only user whose Connect hasn't synced yet. A
    /// counter that counts *down* is worse than one that is merely stale, so
    /// the last usable contribution stays as a floor under today's numbers:
    ///
    /// - it is **never summed**, only ever a term of the same `max`;
    /// - it is **surrendered the instant HealthKit exceeds it** — no latch,
    ///   the merge takes the larger of the two on every single pass;
    /// - it **dies at local midnight**, like every other overlay here (#144,
    ///   #152, #203);
    /// - `freshnessHorizon` decides only whether an arriving snapshot is fresh
    ///   enough to **raise** the floor, never whether the floor still applies.
    struct Floor: Codable, Equatable, Sendable {
        var contribution: Contribution
        /// Local start-of-day the floor belongs to.
        var day: Date
    }

    /// Why a snapshot may not become the day's overlay — one case per gate, so
    /// a refusal can be asserted in a test and surfaced by a future debug view
    /// instead of vanishing (this target logs nothing, by rule).
    enum Usability: String, Equatable, Sendable {
        case usable
        /// Stamped another local day. "Recent" is not the same question as
        /// "today": a snapshot from 23:50 is twenty minutes old at 00:10 and
        /// describes a day that is over — the bug behind #144, #152 and #203.
        case otherDay
        /// Same day, but past `freshnessHorizon`.
        case tooOld
        /// Dated further ahead than `clockSkewTolerance`. A watch clock set
        /// wrong would otherwise refuse every snapshot for good, silently.
        case clockAhead
    }

    /// Whether `snapshot` still speaks for the day `now` falls in, and why not
    /// when it doesn't.
    static func usability(
        _ snapshot: GarminDailySnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> Usability {
        guard calendar.isDate(snapshot.timestamp, inSameDayAs: now) else { return .otherDay }
        let age = now.timeIntervalSince(snapshot.timestamp)
        if age < -clockSkewTolerance { return .clockAhead }
        if age > freshnessHorizon { return .tooOld }
        return .usable
    }

    static func isUsable(_ snapshot: GarminDailySnapshot, now: Date, calendar: Calendar = .current) -> Bool {
        usability(snapshot, now: now, calendar: calendar) == .usable
    }

    /// `snapshot`'s contribution to today, or nil when it has none. This is the
    /// gate that decides whether the floor may be *raised*.
    static func contribution(
        of snapshot: GarminDailySnapshot?,
        now: Date,
        calendar: Calendar = .current
    ) -> Contribution? {
        guard let snapshot, isUsable(snapshot, now: now, calendar: calendar) else { return nil }
        return Contribution(
            steps: max(0, snapshot.steps),
            distanceKm: distanceKm(snapshot),
            activeMinutes: wallClockActiveMinutes(snapshot)
        )
    }

    /// `floor` raised by `contribution`, per metric. A floor from another day
    /// is not raised, it is replaced: yesterday's totals may never carry into
    /// today.
    static func raised(
        _ floor: Floor?,
        with contribution: Contribution,
        now: Date,
        calendar: Calendar = .current
    ) -> Floor {
        let today = calendar.startOfDay(for: now)
        guard let floor, calendar.isDate(floor.day, inSameDayAs: now) else {
            return Floor(contribution: contribution, day: today)
        }
        return Floor(
            contribution: Contribution(
                steps: max(floor.contribution.steps, contribution.steps),
                distanceKm: max(floor.contribution.distanceKm, contribution.distanceKm),
                activeMinutes: max(floor.contribution.activeMinutes, contribution.activeMinutes)
            ),
            day: today
        )
    }

    /// What `floor` still contributes at `now`: everything until local
    /// midnight, nothing after it. Deliberately blind to `freshnessHorizon` —
    /// see `Floor`.
    static func standing(_ floor: Floor?, now: Date, calendar: Calendar = .current) -> Contribution? {
        guard let floor, calendar.isDate(floor.day, inSameDayAs: now) else { return nil }
        return floor.contribution
    }

    /// **The merge.** `healthKit` is what Foulée already knows about today —
    /// its active minutes are themselves `max(appleExerciseTime, workout
    /// minutes)` (see `ActiveMinutes`), so the Connect IQ value joins as a
    /// *third term of that same max*, never as a third addend.
    ///
    /// Clock-free on purpose: whether `overlay` still speaks for today was
    /// decided once, by the caller, against one clock (`standing(_:now:)`).
    ///
    /// Calories are deliberately left alone: `ActivityMonitor.Info.calories` is
    /// Garmin's **total** daily burn, basal metabolism included, while
    /// `activeCalories` here is `activeEnergyBurned`. A max between the two
    /// isn't a double count, it is simply a wrong number — ~400 active kcal
    /// replaced by ~2000 total kcal on the day's first snapshot. The watch
    /// keeps sending the field (the schema is frozen); iOS ignores it.
    static func merged(healthKit: HealthMetrics, overlay: Contribution?) -> HealthMetrics {
        guard let overlay else { return healthKit }
        return HealthMetrics(
            steps: max(healthKit.steps, overlay.steps),
            distanceKm: max(healthKit.distanceKm, overlay.distanceKm),
            activeMinutes: ActiveMinutes.merged(healthKit.activeMinutes, with: overlay.activeMinutes),
            activeCalories: healthKit.activeCalories
        )
    }

    /// Wall-clock active minutes behind a Garmin daily total.
    ///
    /// `ActivityMonitor.ActiveMinutes.total` is Garmin's *intensity* minutes:
    /// moderate activity counts once, vigorous activity counts twice
    /// (`total = moderate + 2 × vigorous`) — which is why #188 sends the
    /// vigorous share as its own field. `appleExerciseTime` counts wall clock,
    /// so comparing the raw totals would credit a 30-minute run as 60 minutes.
    /// Taking the doubled share back out gives `moderate + vigorous`, i.e.
    /// `total − vigorous`.
    ///
    /// Clamped to `0...ActiveMinutes.dailyCap`. When a device family reports a
    /// vigorous count above its own total, the subtraction under-credits — the
    /// deliberate direction: this overlay may only ever be a floor under
    /// HealthKit, never a source of minutes the user did not earn.
    static func wallClockActiveMinutes(_ snapshot: GarminDailySnapshot) -> Int {
        min(max(snapshot.activeMinutes - snapshot.activeMinutesVigorous, 0), ActiveMinutes.dailyCap)
    }

    /// Garmin reports `ActivityMonitor.Info.distance` in centimetres.
    static func distanceKm(_ snapshot: GarminDailySnapshot) -> Double {
        Double(max(0, snapshot.distanceCm)) / 100_000
    }
}
