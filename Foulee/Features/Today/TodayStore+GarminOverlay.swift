import Dependencies
import Foundation

/// Where the Connect IQ snapshot enters the Today pass (issue #189). Split out
/// of `TodayStore.swift` to keep that file within the length limit.
extension TodayStore {
    /// This pass's HealthKit metrics with the Garmin overlay folded in.
    ///
    /// `fetched` is nil when the metrics read was refused, and that decides
    /// everything: the overlay **rides the metrics leg**, exactly like the
    /// post-walk `PendingWalk` one. A refused read stays `.zero` here, so
    /// `isMetricsKnown` is false and `widgetPublication(stored:)` carries the
    /// stored counters forward untouched — a value only the watch measured can
    /// never reach the app group, the Watch or the widgets on its own (#201).
    /// The per-leg discipline of #200/#201 keeps exactly the shape it had.
    ///
    /// The merge itself — max per metric per day, never a sum, never written
    /// back into HealthKit — is `GarminSnapshotOverlay`. What the watch already
    /// measured today stays as a floor under the counters until local midnight,
    /// even once no fresh snapshot can replace it (`GarminSnapshotOverlay.Floor`).
    func metricsWithGarminOverlay(_ fetched: HealthMetrics?) -> HealthMetrics {
        @Dependency(\.garminConnectIQ) var garminConnectIQ
        @Dependency(\.date) var date
        guard let fetched else { return .zero }
        return GarminSnapshotOverlay.merged(healthKit: fetched, overlay: garminConnectIQ.todayOverlay(date.now))
    }
}
