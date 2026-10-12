import CoreLocation
import FouleeKit
import HealthKit
import os

/// Reading back the routes the watch saves with each leg (issues #312, #319).
///
/// **Best effort, end to end.** A route is decoration on a detail that stands
/// without it: a workout with no route, a route the user would not let Foulée
/// read, a query that fails — each yields no segment, never an error that
/// costs the heart rate and the stats beside it.

/// One segment per leg that has a route, in leg order.
nonisolated func fetchRouteSegments(for summary: WorkoutSummary, store: HKHealthStore) async -> [RouteSegment] {
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
nonisolated private func fetchRouteCoordinates(of workout: HKWorkout, store: HKHealthStore) async throws -> [Coordinate] {
    let routes = try await fetchRoutes(of: workout, store: store)
    var coordinates: [Coordinate] = []
    for route in routes {
        coordinates += try await fetchLocations(of: route, store: store).map { Coordinate($0.coordinate) }
    }
    return coordinates
}

nonisolated private func fetchRoutes(of workout: HKWorkout, store: HKHealthStore) async throws -> [HKWorkoutRoute] {
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
nonisolated private func fetchLocations(of route: HKWorkoutRoute, store: HKHealthStore) async throws -> [CLLocation] {
    /// HealthKit calls the handler serially, one batch after another. The lock
    /// costs nothing in that case and turns the promise into something the
    /// compiler checks, instead of an `@unchecked Sendable` (issue #405).
    nonisolated struct Batches: Sendable {
        var locations: [CLLocation] = []
        var isFinished = false
    }
    /// What the handler decided, read outside the lock: resuming a
    /// continuation from inside it would hold the lock across the resume.
    enum Outcome: Sendable {
        case pending
        case failed(any Error)
        case finished([CLLocation])
    }
    let batches = OSAllocatedUnfairLock(initialState: Batches())
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
            let outcome = batches.withLock { state -> Outcome in
                guard !state.isFinished else { return .pending }
                if let error {
                    state.isFinished = true
                    return .failed(error)
                }
                state.locations += batch ?? []
                guard done else { return .pending }
                state.isFinished = true
                return .finished(state.locations)
            }
            switch outcome {
            case .pending: break
            case .failed(let error): continuation.resume(throwing: error)
            case .finished(let locations): continuation.resume(returning: locations)
            }
        }
        store.execute(query)
    }
}
