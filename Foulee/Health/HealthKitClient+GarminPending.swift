import FouleeKit
import Foundation
import HealthKit

// The Garmin outings Santé doesn't have yet (ADR 0009, D2), on the HealthKit
// side of the résumé and its detail. Separate file to keep
// HealthKitClient+Live.swift within the file-length limit.

/// The résumé's workouts of the last `daysBack` days: Santé's, plus the
/// Garmin outings it doesn't have yet (ADR 0009, D2; #479), the parts of an
/// outing the wearer merged stamped as its legs (#549). Newest first.
///
/// The merges are applied here, once, so every reader — the Bilan, the
/// session's highlight, its notification — sees the merged outing.
nonisolated func recentWorkoutSummaries(
    store: HKHealthStore,
    daysBack: Int
) async throws -> [WorkoutSummary] {
    let healthKit = OutingMerges.applying(
        OutingMergeStore.read(),
        to: try await healthKitWorkoutSummaries(store: store, daysBack: daysBack)
    )
    guard let window = WorkoutActivityFilter.recentWindow(daysBack: daysBack) else { return healthKit }
    let pending = GarminPendingOutingStore.remaining(healthKitWorkouts: healthKit.map {
        ActiveMinutes.WorkoutInterval(start: $0.startedAt, duration: $0.durationSeconds)
    })
    return (healthKit + GarminPendingOutings.workouts(pending, startingIn: window))
        .sorted { $0.startedAt > $1.startedAt }
}

/// The detail of a row HealthKit can't give one for: a pending Garmin outing,
/// with the route its watch sent, or a workout that disappeared in between.
nonisolated func summaryOnlyDetail(of summary: WorkoutSummary) -> WorkoutDetail {
    WorkoutDetail(
        summary: summary,
        heartRateSamples: [],
        stepsCount: summary.steps,
        route: GarminPendingOutings.route(of: summary, in: GarminPendingOutingStore.read())
    )
}
