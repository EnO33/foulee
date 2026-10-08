import CoreLocation
import HealthKit

/// Reading back the routes the watch saves with each leg (issues #312, #319).
///
/// **Best effort, end to end.** A route is decoration on a detail that stands
/// without it: a workout with no route, a route the user would not let Foulée
/// read, a query that fails — each yields no segment, never an error that
/// costs the heart rate and the stats beside it.

/// One segment per leg that has a route, in leg order.
func fetchRouteSegments(for summary: WorkoutSummary, store: HKHealthStore) async -> [RouteSegment] {
    var segments: [RouteSegment] = []
    for leg in RouteSegment.sources(of: summary) {
        guard !Task.isCancelled else { break }
        guard let workout = try? await fetchWorkout(uuid: leg.id, store: store),
              let coordinates = try? await fetchRouteCoordinates(of: workout, store: store),
              coordinates.count >= 2
        else { continue }
        segments.append(RouteSegment(id: leg.id, activity: leg.activity, coordinates: coordinates))
    }
    return segments
}

/// Every point of every `HKWorkoutRoute` attached to `workout`, oldest first.
private func fetchRouteCoordinates(of workout: HKWorkout, store: HKHealthStore) async throws -> [Coordinate] {
    let routes = try await fetchRoutes(of: workout, store: store)
    var coordinates: [Coordinate] = []
    for route in routes {
        coordinates += try await fetchLocations(of: route, store: store).map { Coordinate($0.coordinate) }
    }
    return coordinates
}

private func fetchRoutes(of workout: HKWorkout, store: HKHealthStore) async throws -> [HKWorkoutRoute] {
    try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: HKSeriesType.workoutRoute(),
            predicate: HKQuery.predicateForObjects(from: workout),
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, error in
            if isNoDataAvailable(error) {
                continuation.resume(returning: [])
                return
            }
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
        }
        store.execute(query)
    }
}

/// The route's points. `HKWorkoutRouteQuery` hands them over **in batches**
/// and says when it is done — resuming on the first batch would draw a route
/// that stops a few hundred metres in.
///
/// Not cancelled mid-query: `HKHealthStore.stop` does not promise to call the
/// handler again, and a continuation left waiting would leak. A route is a
/// bounded read; leaving the detail stops the loop in `fetchRouteSegments`
/// between two legs instead.
private func fetchLocations(of route: HKWorkoutRoute, store: HKHealthStore) async throws -> [CLLocation] {
    /// HealthKit calls the handler serially, one batch after another, so the
    /// mutable state is never touched from two threads at once.
    final class Batches: @unchecked Sendable {
        var locations: [CLLocation] = []
        var isFinished = false
    }
    let batches = Batches()
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
            guard !batches.isFinished else { return }
            if let error {
                batches.isFinished = true
                continuation.resume(throwing: error)
                return
            }
            batches.locations += batch ?? []
            guard done else { return }
            batches.isFinished = true
            continuation.resume(returning: batches.locations)
        }
        store.execute(query)
    }
}
