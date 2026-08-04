import Foundation

/// What a refresh pass hands to the outside world, and the per-leg rule that
/// decides it. Split out of `TodayStore.swift` to keep that file within the
/// length limit.
extension TodayStore {
    /// The app-group snapshot the widgets read, plus the payload for the
    /// Watch — nil when this pass measured no streak.
    struct Publication {
        var snapshot: WidgetSnapshot
        var watchPayload: WatchSyncPayload?
    }

    /// Project the current snapshot onto `stored` — the app group as it stands
    /// right now. Pure (and internal) so the rules below are testable without
    /// racing on the process-global app group.
    ///
    /// Per-leg discipline, same as `refreshSnapshotMetrics` on the background
    /// path: a leg nobody could read keeps the stored value instead of
    /// publishing a zero. Two legs feed a pass — the history behind the streak
    /// (issue #200) and today's metrics behind the counters (issue #201) — and
    /// each fails on its own. The in-app snapshot may still show the zeros a
    /// failure computed; the error banner explains them. What must never
    /// happen is overwriting a shared value with a number nobody measured.
    func widgetPublication(stored: WidgetSnapshot?) -> Publication? {
        guard let snapshot else { return nil }
        // Stale-zeroed first: what carries forward is "the last known values
        // *for today*". A snapshot stamped yesterday knows nothing about
        // today, so it contributes zeros rather than resurrecting yesterday's
        // totals under today's stamp (issues #144, #152).
        let carried = stored?.zeroedIfStale()
        var published = WidgetSnapshot(
            steps: snapshot.steps,
            stepsGoal: snapshot.stepsGoal,
            minutes: snapshot.minutes,
            minutesGoal: snapshot.minutesGoal,
            distanceKm: snapshot.distanceKm,
            calories: snapshot.calories,
            streak: snapshot.streak,
            // Water intake is owned by the hydration flow, never measured by a
            // refresh pass — always carried forward so this full rewrite
            // doesn't reset the ring, whichever leg failed.
            waterML: carried?.waterML ?? 0,
            waterGoalML: hydrationGoalML,
            hydrationEnabled: hydrationEnabled,
            hydrationGlassML: hydrationGlassML
        )
        if let carried {
            // Field-by-field commits, mirroring the background path's `if let`.
            // With nothing stored (first install) the computed zeros go out
            // anyway: they can't overwrite a value anyone measured.
            // The post-walk overlay rides this leg too, so a refused read
            // doesn't republish it — the refresh that ended the walk already
            // wrote it to the app group, and the next pass restores it.
            if !isMetricsKnown {
                published.steps = carried.steps
                published.minutes = carried.minutes
                published.distanceKm = carried.distanceKm
                published.calories = carried.calories
            }
            if !isHistoryKnown { published.streak = carried.streak }
        }
        // No push at all when the streak is unmeasured: the Watch keeps the
        // last value the phone actually computed, rather than one nobody did.
        // A failed metrics leg doesn't suppress it — the payload carries the
        // streak, the goals and the hydration prefs, no counters at all, so
        // withholding it would only starve the Watch of data that is fine.
        guard isHistoryKnown else { return Publication(snapshot: published, watchPayload: nil) }
        return Publication(snapshot: published, watchPayload: WatchSyncPayload(
            streak: snapshot.streak,
            minutesGoal: minutesGoal,
            stepsGoal: stepsGoal,
            hydrationEnabled: hydrationEnabled,
            hydrationGoalML: hydrationGoalML,
            hydrationGlassML: hydrationGlassML
        ))
    }
}
