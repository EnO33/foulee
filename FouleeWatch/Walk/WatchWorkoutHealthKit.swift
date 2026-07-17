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
                // The data source infers the types to collect from the config —
                // distance, active energy and heart rate for a walk, but NOT step
                // count. Enable it explicitly, otherwise the live "pas" counter
                // stays at 0 while distance and heart rate update.
                dataSource.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
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
