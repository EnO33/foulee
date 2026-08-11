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
    /// - Parameter at: when the leg begins. **May be in the past** (issue
    ///   #265): a leg opened at a detected boundary starts when the wearer
    ///   changed sport, not when we noticed. Dating it `.now` would leave the
    ///   seconds in between belonging to neither leg.
    var startSession: @MainActor (
        _ configuration: HKWorkoutConfiguration,
        _ at: Date,
        _ delegate: any HKWorkoutSessionDelegate & HKLiveWorkoutBuilderDelegate
    ) async throws -> WatchWorkoutSessionHandle
}

/// One live session/builder pair reduced to the operations the store needs.
/// The closures are the only strong references to the underlying HK objects,
/// so releasing the handle releases the builder — the store's save/retry
/// logic relies on exactly that.
struct WatchWorkoutSessionHandle: Sendable {
    /// Identifies the underlying `HKWorkoutSession`, and its builder.
    ///
    /// The store is the delegate of **every** session it opens, and since issue
    /// #265 an outing opens one per leg. HealthKit hands the delegate the object
    /// that is calling, and nothing else — so without these the store cannot
    /// tell a callback about the leg in flight from one about a leg it closed a
    /// moment ago (issue #290). It could not, and it killed the outing on the
    /// second switch.
    ///
    /// `ObjectIdentifier` rather than the objects themselves: this is identity,
    /// not access, and a stub can name any object it likes.
    var sessionID: ObjectIdentifier
    var builderID: ObjectIdentifier
    /// Offer this session to the paired iPhone (issue #277).
    ///
    /// Separate from `startSession` and allowed to throw on its own, because a
    /// mirror that will not open is **not** a reason to lose a sortie. The
    /// store logs the refusal and carries on recording; nothing on the wrist
    /// depends on the phone being there.
    ///
    /// The direction is not a choice: `startMirroringToCompanionDevice()`
    /// exists only on watchOS, and `HKWorkoutSessionType` has exactly
    /// `primary` and `mirrored`. The watch is always the engine — there is no
    /// API for the reverse and there will not be one.
    var startMirroring: @MainActor () async throws -> Void
    /// Hand a snapshot to the mirrored session on the iPhone (issue #278).
    ///
    /// Throwing is the ordinary case, not the exception: there is nothing to
    /// send to when no phone is mirroring. The store swallows it — a wrist that
    /// stopped sending is still a wrist that is recording.
    var sendToRemote: @MainActor (Data) async throws -> Void
    var end: @MainActor () -> Void
    var endCollection: @MainActor (_ at: Date) async throws -> Void
    var finishWorkout: @MainActor () async throws -> Void
    /// `HKLiveWorkoutBuilder.endDate` — non-nil once collection has ended, so
    /// a retry knows not to end it twice.
    var collectionEndDate: @MainActor () -> Date?
    // No way to open or close a nested activity, and there will not be one:
    // HealthKit refuses a subactivity whose sport differs from the session's
    // own (« Cannot add subactivity of type HKWorkoutActivityTypeRunning »,
    // observed on a wrist). A change of sport ends this leg and opens another
    // session instead — issue #265, which is how Forme does it too.
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
            startSession: { configuration, startDate, delegate in
                let session = try HKWorkoutSession(
                    healthStore: store,
                    configuration: configuration
                )
                let builder = session.associatedWorkoutBuilder()
                let dataSource = makeDataSource(healthStore: store, configuration: configuration)
                builder.dataSource = dataSource
                session.delegate = delegate
                builder.delegate = delegate

                session.startActivity(with: startDate)
                try await builder.beginCollection(at: startDate)

                return WatchWorkoutSessionHandle(
                    sessionID: ObjectIdentifier(session),
                    builderID: ObjectIdentifier(builder),
                    startMirroring: { try await session.startMirroringToCompanionDevice() },
                    sendToRemote: { try await session.sendToRemoteWorkoutSession(data: $0) },
                    end: { session.end() },
                    endCollection: { try await builder.endCollection(at: $0) },
                    finishWorkout: { _ = try await builder.finishWorkout() },
                    collectionEndDate: { builder.endDate }
                )
            }
        )
    }
}
