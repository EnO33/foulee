@preconcurrency import HealthKit

/// The HealthKit side effects `WatchWorkoutStore` drives, as an injectable
/// struct-of-closures (the watch target doesn't link the Dependencies
/// package). `.live` talks to `HKWorkoutSession`/`HKLiveWorkoutBuilder`;
/// tests swap in stubs to exercise the state machine deterministically.
struct WatchWorkoutHealthKit: Sendable {
    var isAvailable: @MainActor () -> Bool
    /// Throws only when the request itself fails — denial is silent, by
    /// HealthKit design.
    var requestAuthorization: @MainActor (
        _ toShare: Set<HKSampleType>,
        _ read: Set<HKObjectType>
    ) async throws -> Void
    /// Creates, wires and starts a live session, returning a handle to its
    /// lifecycle. The delegate keeps receiving session/builder callbacks
    /// directly — that is how the store's `ingest` gets live metrics.
    var startSession: @MainActor (
        _ configuration: HKWorkoutConfiguration,
        _ delegate: any HKWorkoutSessionDelegate & HKLiveWorkoutBuilderDelegate
    ) async throws -> WatchWorkoutSessionHandle
}

/// One live session/builder pair reduced to the operations the store needs.
/// The closures are the only strong references to the underlying HK objects,
/// so releasing the handle releases the builder — the store's save/retry
/// logic relies on exactly that.
struct WatchWorkoutSessionHandle: Sendable {
    var end: @MainActor () -> Void
    var endCollection: @MainActor (_ at: Date) async throws -> Void
    var finishWorkout: @MainActor () async throws -> Void
    /// `HKLiveWorkoutBuilder.endDate` — non-nil once collection has ended, so
    /// a retry knows not to end it twice.
    var collectionEndDate: @MainActor () -> Date?
}

/// The quantity types a live session collects, and the single list the whole
/// watch workout path is built from: `WatchWorkoutHealthKit.live` force-enables
/// exactly these on the data source, `WatchWorkoutStore` asks to share and read
/// exactly these (plus the workout type itself), and `ingest` reads back
/// exactly these. Three lists that had to agree by hand — a type collected but
/// not shareable is what makes `finishWorkout()` fail with an authorization
/// error, and a type read back but never collected is a counter frozen at 0.
let collectedQuantityTypes: [HKQuantityType] = [
    HKQuantityType(.stepCount),
    HKQuantityType(.distanceWalkingRunning),
    HKQuantityType(.activeEnergyBurned),
    HKQuantityType(.heartRate)
]

extension WatchWorkoutHealthKit {
    @MainActor static var live: WatchWorkoutHealthKit {
        let store = HKHealthStore()
        return WatchWorkoutHealthKit(
            isAvailable: { HKHealthStore.isHealthDataAvailable() },
            requestAuthorization: { toShare, read in
                try await store.requestAuthorization(toShare: toShare, read: read)
            },
            startSession: { configuration, delegate in
                let session = try HKWorkoutSession(
                    healthStore: store,
                    configuration: configuration
                )
                let builder = session.associatedWorkoutBuilder()
                let dataSource = HKLiveWorkoutDataSource(
                    healthStore: store,
                    workoutConfiguration: configuration
                )
                // The data source infers the types to collect from the config.
                // For a walk that inference was measured: distance, active
                // energy and heart rate, but NOT step count — hence the
                // explicit enable, without which the live "pas" counter stayed
                // at 0 while distance and heart rate updated.
                //
                // What it infers for `.running` is NOT established, and cannot
                // be without a real watch (the simulator has no sensors). So
                // don't depend on it: enable every type `WatchWorkoutStore`
                // reads back in `ingest` — enabling one the source would have
                // inferred anyway is a no-op, while missing one silently zeroes
                // a live counter for the whole session (issue #223). The set is
                // the same for both activities on purpose: a run reports its
                // distance under the same `distanceWalkingRunning` type a walk
                // does, so there is nothing to branch on.
                for type in collectedQuantityTypes {
                    dataSource.enableCollection(for: type, predicate: nil)
                }
                builder.dataSource = dataSource
                session.delegate = delegate
                builder.delegate = delegate

                let startDate = Date()
                session.startActivity(with: startDate)
                try await builder.beginCollection(at: startDate)

                return WatchWorkoutSessionHandle(
                    end: { session.end() },
                    endCollection: { try await builder.endCollection(at: $0) },
                    finishWorkout: { _ = try await builder.finishWorkout() },
                    collectionEndDate: { builder.endDate }
                )
            }
        )
    }
}
