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
    /// Open a nested `HKWorkoutActivity` inside the running session (issue
    /// #249), dated `at` — which may be in the past, and usually is: the
    /// boundary comes from CoreMotion's own stamp for when the activity began,
    /// not from when we noticed.
    ///
    /// This is not a relabelling. Apple's header is explicit that « sensor
    /// algorithms to generate data would be updated to match the new
    /// activity », so the watch *measures differently* afterwards.
    var beginActivity: @MainActor (_ configuration: HKWorkoutConfiguration, _ at: Date) -> Void
    /// Close the running nested activity. HealthKit's own word for it is
    /// « reverting to the main session activity »; Foulée immediately opens the
    /// next segment, so the main activity is never what is actually recording.
    var endCurrentActivity: @MainActor (_ at: Date) -> Void
    /// Every segment HealthKit has recorded for this session, oldest first,
    /// including the one in flight (issue #250).
    var segments: @MainActor () -> [WatchWorkoutSegment]
}

/// The quantity types a live session collects, and the single list the whole
/// watch workout path is built from: `makeDataSource` force-enables exactly
/// these on the data source, `WatchWorkoutStore` asks to share and read
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
    /// The live data source for `configuration`, with every type the store
    /// reads back in `ingest` force-enabled.
    ///
    /// The data source infers the types to collect from the config, and the
    /// inference is not the same for both activities. It is not a mystery
    /// either: `typesToCollect` is the source's own answer and reads fine in
    /// the simulator, so `WatchWorkoutCollectionTests` holds what it actually
    /// says. For `.walking` it omits step count — which is why the explicit
    /// enable exists at all: without it the live "pas" counter stayed at 0
    /// while distance and heart rate updated. For `.running` it already infers
    /// step count too, so the enable changes nothing there.
    ///
    /// Enable them anyway rather than depend on that: enabling a type the
    /// source would have inferred is a no-op, while missing one silently zeroes
    /// a live counter for a whole session (issue #223). The set is the same for
    /// both activities on purpose: a run reports its distance under the same
    /// `distanceWalkingRunning` type a walk does, so there is nothing to branch
    /// on.
    ///
    /// Split out of `live` because that closure also builds an
    /// `HKWorkoutSession`, which needs a real watch — this part does not, and
    /// it is the part that can be got wrong.
    @MainActor static func makeDataSource(
        healthStore: HKHealthStore,
        configuration: HKWorkoutConfiguration
    ) -> HKLiveWorkoutDataSource {
        let dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        for type in collectedQuantityTypes {
            dataSource.enableCollection(for: type, predicate: nil)
        }
        return dataSource
    }

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
                let dataSource = makeDataSource(healthStore: store, configuration: configuration)
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
                    collectionEndDate: { builder.endDate },
                    beginActivity: { configuration, date in
                        session.beginNewActivity(configuration: configuration, date: date, metadata: nil)
                    },
                    endCurrentActivity: { session.endCurrentActivity(on: $0) },
                    // Two readings of the same list, merged rather than chosen
                    // between. `workoutActivities` is documented in terms of
                    // the *manual* `addWorkoutActivity:` path, so whether it
                    // also carries the ones a session began is not something
                    // this can assert; `currentWorkoutActivity` is documented
                    // to hold the one in flight and to go nil the moment it
                    // ends. Reading both, and letting the store fold in what
                    // the delegate saw end, covers every combination without
                    // betting on any.
                    segments: {
                        WatchWorkoutSegment.merged([
                            builder.workoutActivities.compactMap(WatchWorkoutSegment.init),
                            [builder.currentWorkoutActivity].compactMap { $0 }.compactMap(WatchWorkoutSegment.init)
                        ])
                    }
                )
            }
        )
    }
}
