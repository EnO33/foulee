import Foundation
import WidgetKit

/// The app's side of the Connect IQ stream (issue #189): what happens to a
/// snapshot once `GarminConnectIQClient` has decoded it. The BLE plumbing stays
/// where #187 put it (`GarminConnectIQBridge`).
///
/// **Scope.** Ingestion, the day-stamped overlay and the widget refresh it
/// needs. Publishing the watch app to the Connect IQ store (#190), reading
/// hydration from the watch, and any UI beyond the numbers already on screen
/// are all out — nothing here adds a screen or a setting.
enum GarminSnapshotIngestion {
    /// What became of a decoded snapshot. A value rather than a log line: this
    /// target has no logger by rule, and a refusal that leaves no trace at all
    /// is how a wrong watch clock could silently cost a user the whole feature
    /// (`GarminSnapshotStore.lastOutcome` keeps the latest one).
    enum Outcome: String, Equatable, Sendable {
        case accepted
        case otherDay
        case tooOld
        case clockAhead
        case superseded
    }

    /// Floor between two widget reloads spent by this channel.
    ///
    /// The same cadence the timelines themselves ask for
    /// (`WidgetRefresh.daytimeStepMinutes`): WidgetKit grants roughly 40-70
    /// reloads a day, and the watch pushes every five minutes *because* its own
    /// metrics moved — so "the counters changed" is true on essentially every
    /// accepted snapshot and cannot be the only gate.
    static let reloadThrottle = TimeInterval(WidgetRefresh.daytimeStepMinutes * 60)

    private static let lastReloadKey = "garmin.connectiq.lastPublishAt"

    /// Take `snapshot` as the day's overlay when it earns the place, and report
    /// what happened either way.
    ///
    /// Two independent gates, in this order:
    ///
    /// 1. **Freshness** (`GarminSnapshotOverlay.usability`) — a snapshot that is
    ///    already stale on arrival (the watch reconnected after hours out of
    ///    range, or its clock is wrong) may not raise the day's floor: it would
    ///    outrank HealthKit with a total from another time, or another day.
    /// 2. **Ordering** (`GarminDailySnapshot.supersedes`, #187) — BLE reorders
    ///    and redelivers, so the watch's own generation counter decides.
    ///    Compared against the *usable* stored snapshot, never the raw record:
    ///    an expired one must not keep blocking, which is also how a watch-side
    ///    counter reset (app reinstall) recovers on its own within the horizon.
    ///
    /// An accepted snapshot raises the day's high-water floor, and that floor —
    /// not this record — is what the counters read: it outlives the freshness
    /// horizon, the snapshot behind it does not (`GarminSnapshotOverlay.Floor`).
    @discardableResult
    static func accept(
        _ snapshot: GarminDailySnapshot,
        now: Date = .now,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> Outcome {
        let outcome = verdict(snapshot, now: now, defaults: defaults, calendar: calendar)
        GarminSnapshotStore.recordOutcome(outcome, to: defaults)
        guard outcome == .accepted,
              let contribution = GarminSnapshotOverlay.contribution(of: snapshot, now: now, calendar: calendar)
        else { return outcome }
        GarminSnapshotStore.write(snapshot, to: defaults)
        GarminSnapshotStore.raiseFloor(with: contribution, now: now, to: defaults, calendar: calendar)
        return outcome
    }

    private static func verdict(
        _ snapshot: GarminDailySnapshot,
        now: Date,
        defaults: UserDefaults,
        calendar: Calendar
    ) -> Outcome {
        switch GarminSnapshotOverlay.usability(snapshot, now: now, calendar: calendar) {
        case .otherDay: return .otherDay
        case .tooOld: return .tooOld
        case .clockAhead: return .clockAhead
        case .usable: break
        }
        let previous = GarminSnapshotStore.read(now: now, from: defaults, calendar: calendar)
        return GarminDailySnapshot.supersedes(snapshot, lastAccepted: previous) ? .accepted : .superseded
    }

    /// Drains the client's snapshot stream for the lifetime of the process.
    static func run(_ snapshots: AsyncStream<GarminDailySnapshot>) async {
        for await snapshot in snapshots where accept(snapshot) == .accepted {
            await publish()
        }
    }

    /// When this channel last spent a widget reload, or nil when it never did.
    /// A stamp in the future — clock pushed forward then back — counts as none,
    /// same reasoning as `BackgroundStreakRefresh.lastRecomputeAt`: honouring it
    /// would wedge the reload for an unbounded time instead of ten minutes.
    static func lastReloadAt(defaults: UserDefaults = .standard, now: Date = .now) -> Date? {
        let stamp = defaults.double(forKey: lastReloadKey)
        guard stamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: stamp)
        return date <= now ? date : nil
    }

    static func markReloaded(at date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date.timeIntervalSince1970, forKey: lastReloadKey)
    }

    /// Whether an accepted snapshot is worth a widget reload. Pure, so the
    /// budget rule is testable.
    ///
    /// Both gates matter. `countersMoved` drops the pushes that changed nothing
    /// the widgets show; the throttle caps what is left, because the watch
    /// transmits *because* its metrics moved — so without it this channel alone
    /// would ask for a reload every five minutes all day and blow the 40-70/day
    /// budget on its own. Only the reload is rationed: the store write always
    /// happens, so the app group stays current for the app, the Watch and the
    /// next background wake, and the widgets pick the value up on their next
    /// scheduled timeline (`WidgetRefresh`) at the latest.
    static func shouldReloadWidgets(countersMoved: Bool, lastReloadAt: Date?, now: Date) -> Bool {
        guard countersMoved else { return false }
        guard let lastReloadAt else { return true }
        return now.timeIntervalSince(lastReloadAt) >= reloadThrottle
    }

    /// Rebuild the shared snapshot with the new overlay folded in, then reload
    /// the widgets it can actually have moved.
    ///
    /// This channel writes no HealthKit sample — that is the whole point — so
    /// no observer fires and nothing else would ever refresh the widgets here.
    /// The reload is therefore explicit, but targeted (`reloadTimelines(ofKind:)`
    /// over the counter widgets, not `reloadAllTimelines`) and rationed
    /// (`shouldReloadWidgets`).
    ///
    /// The rebuild goes through the ordinary HealthKit path, which folds the
    /// overlay onto the legs HealthKit answered and keeps the stored value for
    /// the ones it refused. A locked phone therefore defers the freshness gain
    /// to the next successful read rather than publishing a Garmin total on
    /// top of counters nobody could measure.
    private static func publish() async {
        let before = SharedStore.read()
        await refreshWidgetSnapshotFromHealth()
        let after = SharedStore.read()
        let now = Date.now
        guard shouldReloadWidgets(
            countersMoved: before?.counters != after?.counters,
            lastReloadAt: lastReloadAt(now: now),
            now: now
        ) else { return }
        markReloaded(at: now)
        for kind in WidgetKind.counters {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
