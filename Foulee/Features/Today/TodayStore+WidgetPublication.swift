import Dependencies
import Foundation
import WidgetKit

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

    /// Mirror the current snapshot into the shared app group and refresh the
    /// widgets. Widgets can't read HealthKit while the phone is locked, so they
    /// read this snapshot instead — which keeps the Lock Screen from dropping to
    /// zero. Cheap; safe to call on every refresh / goal change.
    ///
    /// Lives here rather than in `TodayStore.swift` for the reason that file
    /// exists at all — it is at the length limit — and it belongs next to the
    /// projection it publishes.
    func publishToWidgets() {
        guard let publication = widgetPublication(stored: SharedStore.read()) else { return }
        SharedStore.write(publication.snapshot)
        WidgetCenter.shared.reloadAllTimelines()

        // Push the phone-computed streak (+ goals) to the Watch. The watch's
        // local HealthKit only keeps a few days of history, so it can't
        // recompute long streaks correctly — it just displays this value.
        guard let payload = publication.watchPayload else { return }
        PhoneWatchSync.shared.send(payload)
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
        // How much of those counters the widget process cannot re-measure rides
        // along with them (#214), so it can apply the same `max` the background
        // path does. It has no way to work this out itself: `GarminSnapshotStore`
        // lives in the app's own defaults, and `pendingWalk` only in this
        // object's memory.
        //
        // Two contributors, one number per counter. Minutes see the watch only
        // — the post-walk overlay deliberately never fakes exercise minutes, so
        // there is nothing of it to carry there.
        //
        // Computed unconditionally, unlike the counters above: both legs are a
        // different channel entirely. The watch's arrives over BLE and is read
        // from local storage, so there is no "unknown" case to carry forward —
        // `todayOverlay` cannot fail, it answers nil only when nothing speaks
        // for today — and `GarminSnapshotOverlay.standing` has already dropped a
        // floor stamped another day; the walk's is this process's own memory.
        // Gating them on `isMetricsKnown` would blank a floor that is still
        // perfectly valid whenever Santé was locked.
        //
        // Clamped to the counters they accompany, though, which is what keeps
        // the snapshot internally consistent: on a refused metrics leg with
        // nothing stored the published counters are zeros (#201), and a floor
        // left standing above them would let the widget rebuild the watch's day
        // out of a snapshot the app itself is showing as 0 behind its error
        // banner. A floor may hold a total up; it may never invent one.
        @Dependency(\.garminConnectIQ) var garminConnectIQ
        @Dependency(\.date) var date
        let watch = garminConnectIQ.todayOverlay(date.now)
        let walk = pendingWalkFloor
        published.floorSteps = min(max(watch?.steps ?? 0, walk?.steps ?? 0), published.steps)
        published.floorMinutes = min(watch?.activeMinutes ?? 0, published.minutes)
        published.floorDistanceKm = min(
            max(watch?.distanceKm ?? 0, walk?.distanceKm ?? 0),
            published.distanceKm
        )
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
            hydrationGlassML: hydrationGlassML,
            activityMode: activityMode
        ))
    }
}
