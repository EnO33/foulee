import CoreLocation
import FouleeKit
import Foundation
import HealthKit
import Testing
@testable import FouleeWatch

struct StubError: LocalizedError {
    var errorDescription: String? { "boom" }
}

/// Scriptable stand-in for `WatchWorkoutHealthKit.live`: records every call,
/// throws on demand, and tracks the handle's lifetime so tests can assert
/// that the store releases (or deliberately retains) the builder.
@MainActor
final class WorkoutHealthKitStub {
    var isAvailable = true
    var authError: Error?
    var startError: Error?
    var endCollectionError: Error?
    var finishError: Error?
    /// Set to refuse the mirror — a phone that is off, unpaired or out of
    /// range. The sortie must not notice (issue #277).
    var mirrorError: Error?

    private(set) var startCalls = 0
    private(set) var mirrorOffers = 0
    /// Every snapshot handed to the phone, decoded (issue #278).
    private(set) var sentSnapshots: [WatchSessionSnapshot] = []
    /// Whether `end()` had already been called when each snapshot went out.
    /// `sendToRemoteWorkoutSession` needs a session that is still alive, so the
    /// final snapshot has to leave *before* the teardown (issue #278).
    private(set) var sentAfterEnd: [Bool] = []
    /// Set to refuse the send — no phone is mirroring, the ordinary case.
    var sendError: Error?
    /// The types the last `start(activity:)` asked to share. A type the data
    /// source collects but we never asked to share is what makes
    /// `finishWorkout()` fail with an authorization error, so the two lists
    /// agreeing is a real invariant, not bookkeeping.
    private(set) var requestedShareTypes: Set<HKSampleType> = []
    private(set) var requestedReadTypes: Set<HKObjectType> = []
    /// The configuration handed to the last `startSession` — this is verbatim
    /// what HealthKit stamps the saved workout with, so asserting on it is
    /// asserting on what lands in Santé (issue #223).
    private(set) var startedConfiguration: HKWorkoutConfiguration?
    private(set) var endCalls = 0
    private(set) var endCollectionCalls = 0
    private(set) var finishCalls = 0
    private(set) var collectionEndDate: Date?
    /// Every leg opened, with the instant it was told to start (issue #265).
    /// A change of sport ends one session and opens another, so an outing is a
    /// list — and the dates are what say whether the boundary was back-dated.
    private(set) var startedLegs: [(configuration: HKWorkoutConfiguration, at: Date)] = []
    /// Every date a leg was told to stop collecting at.
    private(set) var endCollectionDates: [Date] = []

    /// Weak by design: the only strong reference lives in the handle's
    /// closures, so `nil` here means the store let go of the handle.
    private(set) weak var handleToken: AnyObject?
    /// The identity of every handle handed out, oldest first (issue #290).
    ///
    /// A value, so recording it retains nothing — `handleToken` above still
    /// says whether the store released the builder. This is what lets a test
    /// deliver a callback *as a leg that has already been closed*.
    private(set) var handleIDs: [ObjectIdentifier] = []
    /// What each opened leg was told it is, in call order (issue #316).
    private(set) var outingLegs: [OutingLeg] = []
    /// The route handed to each `finishWorkout`, in call order (issue #312).
    private(set) var finishedRoutes: [[CLLocation]] = []
    /// Called while `finishWorkout` runs — the moment the wearer waits on.
    var onFinish: (() -> Void)?
    /// Suspend inside `endCollection`, as HealthKit does.
    var yieldsWhileSaving = false
    /// `HKWorkoutSession.pause()` and `resume()` calls (issue #384).
    private(set) var pauseCalls = 0
    private(set) var resumeCalls = 0
    /// The climb each leg was stamped with, in call order (issue #535).
    private(set) var climbs: [Elevation] = []
    /// The time the store reads (issue #406). It stands still until a test
    /// moves it, so every date the store writes is one the test can name.
    let clock = ManualClock()
    /// The watch's charge as the store reads it (issue #614): full and
    /// unplugged until a test drains it.
    var battery = BatteryReading(level: 1, isCharging: false)
    /// A session left running by an app that died (issue #554), handed out
    /// once by `recoverSession`.
    var recoverable: RecoverableSession?
    /// What Santé holds for the recovered outing.
    var savedLegs: [WatchWorkoutSegment] = []
    private(set) var recoverCalls = 0
    /// The outings whose saved legs were read back.
    private(set) var savedLegsAsked: [UUID] = []

    func makeStore(
        detection: WatchActivityDetection = WatchActivityDetection(source: .inert, pedometer: .inert),
        route: WatchRouteStore = WatchRouteStore(source: .inert),
        climb: WatchClimbStore = WatchClimbStore(source: .inert)
    ) -> WatchWorkoutStore {
        WatchWorkoutStore(healthKit: WatchWorkoutHealthKit(
            isAvailable: { self.isAvailable },
            requestAuthorization: { toShare, read in
                self.requestedShareTypes = toShare
                self.requestedReadTypes = read
                if let error = self.authError { throw error }
            },
            startSession: { configuration, startDate, leg, _ in
                self.startCalls += 1
                self.startedConfiguration = configuration
                self.startedLegs.append((configuration, startDate))
                self.outingLegs.append(leg)
                if let error = self.startError { throw error }
                return self.makeHandle()
            },
            recoverSession: { _ in
                self.recoverCalls += 1
                guard let session = self.recoverable else { return nil }
                self.recoverable = nil
                return WatchRecoveredSession(
                    handle: self.makeHandle(),
                    activity: session.activity,
                    startedAt: session.startedAt,
                    leg: session.leg,
                    elapsed: session.elapsed,
                    isPaused: session.isPaused
                )
            },
            savedLegs: { outingID in
                self.savedLegsAsked.append(outingID)
                return self.savedLegs
            }
        ), detection: detection, route: route, climb: climb, battery: { self.battery }, clock: clock.read)
    }

    private func makeHandle() -> WatchWorkoutSessionHandle {
        let token = NSObject()
        handleToken = token
        // One object stands for both the session and its builder here. Real
        // HealthKit hands out two, and the store keeps them apart; a stub has
        // nothing to gain from the distinction.
        handleIDs.append(ObjectIdentifier(token))
        return WatchWorkoutSessionHandle(
            sessionID: ObjectIdentifier(token),
            builderID: ObjectIdentifier(token),
            startMirroring: {
                self.mirrorOffers += 1
                if let error = self.mirrorError { throw error }
            },
            sendToRemote: { data in
                if let snapshot = try? JSONDecoder().decode(WatchSessionSnapshot.self, from: data) {
                    self.sentSnapshots.append(snapshot)
                    self.sentAfterEnd.append(self.endCalls > 0)
                }
                if let error = self.sendError { throw error }
            },
            end: {
                _ = token
                self.endCalls += 1
            },
            endCollection: { date in
                self.endCollectionCalls += 1
                // Like the real one, saving gives the main actor back: a second
                // tap can land in between (issue #380).
                if self.yieldsWhileSaving { await Task.yield() }
                if let error = self.endCollectionError { throw error }
                self.collectionEndDate = date
                self.endCollectionDates.append(date)
            },
            finishWorkout: { route in
                self.finishCalls += 1
                self.finishedRoutes.append(route)
                self.onFinish?()
                if let error = self.finishError { throw error }
            },
            collectionEndDate: { self.collectionEndDate },
            pause: { self.pauseCalls += 1 },
            resume: { self.resumeCalls += 1 },
            addClimb: { self.climbs.append($0) }
        )
    }
}

/// What a stub session left running says about itself (issue #554): a
/// `WatchRecoveredSession` without its handle, which the stub makes.
struct RecoverableSession {
    var activity: SessionActivity
    var startedAt: Date
    var leg: OutingLeg?
    var elapsed: TimeInterval
    var isPaused = false
}

@MainActor
@Suite("WatchWorkoutStore state machine")
struct WatchWorkoutStoreTests {
    @Test("start() goes active once authorization succeeds")
    func startActivates() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        #expect(store.state == .active(.zero))
        #expect(store.lastError == nil)
        #expect(stub.startCalls == 1)
    }

    @Test("A run is configured as a run, a walk as a walk", arguments: [
        (SessionActivity.walking, HKWorkoutActivityType.walking),
        (SessionActivity.running, HKWorkoutActivityType.running)
    ])
    func startStampsTheRequestedActivity(
        activity: SessionActivity,
        expected: HKWorkoutActivityType
    ) async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: activity)
        // Until #223 this was `.walking` for both rows: every session the
        // watch ever saved went into Santé as a walk, permanently.
        #expect(stub.startedConfiguration?.activityType == expected)
        // The location type is not part of the change — outdoor either way.
        #expect(stub.startedConfiguration?.locationType == .outdoor)
    }

    @Test("Every collected type is asked for, to share and to read")
    func startAuthorizesEveryCollectedType() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .running)
        // Same list the data source collects (issue #223). Collected but not
        // shareable is exactly the authorization error that makes a perfectly
        // good session fail to save at the end.
        for type in collectedQuantityTypes {
            #expect(stub.requestedShareTypes.contains(type))
            #expect(stub.requestedReadTypes.contains(type))
        }
        #expect(stub.requestedShareTypes.contains(HKWorkoutType.workoutType()))
        #expect(stub.requestedShareTypes.contains(HKSeriesType.workoutRoute()))
    }

    @Test("start() is a no-op while a walk is already active")
    func startWhileActiveIsNoOp() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.start(activity: .walking)
        #expect(stub.startCalls == 1)
        #expect(store.state == .active(.zero))
    }

    @Test("HealthKit unavailable stays idle with an error, no session")
    func unavailableStaysIdle() async {
        let stub = WorkoutHealthKitStub()
        stub.isAvailable = false
        let store = stub.makeStore()
        await store.start(activity: .walking)
        #expect(store.state == .idle)
        #expect(store.lastError == "Santé n'est pas disponible sur cet appareil.")
        #expect(stub.startCalls == 0)
    }

    @Test("A failing authorization request stays idle with the error")
    func authFailureStaysIdle() async {
        let stub = WorkoutHealthKitStub()
        stub.authError = StubError()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        #expect(store.state == .idle)
        #expect(store.lastError == "boom")
        #expect(stub.startCalls == 0)
    }

    @Test("A session that fails to start stays idle with the error")
    func startSessionFailureStaysIdle() async {
        let stub = WorkoutHealthKitStub()
        stub.startError = StubError()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        #expect(store.state == .idle)
        #expect(store.lastError == "boom")
        #expect(stub.startCalls == 1)
    }

    @Test("stop() ends, saves and releases the builder")
    func stopSavesAndReleasesBuilder() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.stop()
        #expect(ended(store) == false)
        #expect(store.lastError == nil)
        #expect(stub.endCalls == 1)
        #expect(stub.endCollectionCalls == 1)
        #expect(stub.finishCalls == 1)
        #expect(stub.handleToken == nil)
    }

    @Test("stop() says it is saving until the summary, and only then (#380)")
    func stopFlagsTheSave() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        var savingWhileFinishing: Bool?
        stub.onFinish = { savingWhileFinishing = store.isSaving }
        await store.stop()
        #expect(savingWhileFinishing == true)
        #expect(store.isSaving == false)
        #expect(ended(store) == false)
    }

    @Test("a second tap on « Arrêter » while saving does nothing (#380)")
    func secondStopIsIgnored() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.yieldsWhileSaving = true
        async let first: Void = store.stop()
        async let second: Void = store.stop()
        _ = await (first, second)
        #expect(stub.endCalls == 1)
        #expect(stub.finishCalls == 1)
    }

    @Test("stop() with a failing save keeps the builder for a retry")
    func stopSaveFailureRetainsBuilder() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.finishError = StubError()
        await store.stop()
        #expect(ended(store) == true)
        #expect(store.lastError == "boom")
        #expect(stub.endCalls == 1)
        #expect(stub.handleToken != nil)
    }

    @Test("retrySave() finishes without re-ending an ended collection")
    func retrySaveSkipsEndedCollection() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.finishError = StubError()
        await store.stop()
        stub.finishError = nil
        await store.retrySave()
        #expect(ended(store) == false)
        #expect(store.lastError == nil)
        // Collection ended during stop(); the retry must not end it twice.
        #expect(stub.endCollectionCalls == 1)
        #expect(stub.finishCalls == 2)
        #expect(stub.handleToken == nil)
    }

    @Test("retrySave() re-ends collection when the first attempt never did")
    func retrySaveRerunsFailedEndCollection() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.endCollectionError = StubError()
        await store.stop()
        #expect(ended(store) == true)
        #expect(stub.finishCalls == 0)
        stub.endCollectionError = nil
        await store.retrySave()
        #expect(stub.endCollectionCalls == 2)
        #expect(stub.finishCalls == 1)
        #expect(ended(store) == false)
    }

    @Test("A retry that fails again keeps the failed state and the builder")
    func retrySaveFailureStaysFailed() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.finishError = StubError()
        await store.stop()
        await store.retrySave()
        #expect(ended(store) == true)
        #expect(store.lastError == "boom")
        #expect(stub.finishCalls == 2)
        #expect(stub.handleToken != nil)
    }

    @Test("retrySave() after a successful save is a no-op")
    func retrySaveAfterSuccessIsNoOp() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.stop()
        await store.retrySave()
        #expect(stub.finishCalls == 1)
        #expect(ended(store) == false)
    }

    @Test("A session failure mid-walk lands on the failed summary, retryable")
    func sessionFailureMidWalk() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        store.handleSessionFailure("session interrompue")
        #expect(ended(store) == true)
        #expect(store.lastError == "session interrompue")
        #expect(stub.handleToken != nil)
        // "Réessayer" can still end collection and save the walk.
        await store.retrySave()
        #expect(ended(store) == false)
        #expect(stub.endCollectionCalls == 1)
        #expect(stub.finishCalls == 1)
    }

    @Test("A session failure outside a walk only records the error")
    func sessionFailureWhenIdle() {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        store.handleSessionFailure("boom")
        #expect(store.state == .idle)
        #expect(store.lastError == "boom")
    }

    @Test("reset() returns to idle and releases the builder")
    func resetReturnsToIdle() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.finishError = StubError()
        await store.stop()
        store.reset()
        #expect(store.state == .idle)
        #expect(store.lastError == nil)
        #expect(stub.handleToken == nil)
    }

    @Test("stop() outside an active walk is a no-op")
    func stopWhenIdleIsNoOp() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.stop()
        #expect(store.state == .idle)
        #expect(stub.endCalls == 0)
    }
}

@MainActor
extension WatchWorkoutStoreTests {
    /// Whether the outing ended, and whether it wants a retry.
    ///
    /// The metrics are no longer compared: since issue #265 an ended outing
    /// carries its legs and a real duration, so `.ended(.zero, …)` could only
    /// ever match by accident. What these tests are about is the *case* and the
    /// flag — that is what they now say.
    func ended(_ store: WatchWorkoutStore) -> Bool? {
        guard case .ended(_, let saveFailed) = store.state else { return nil }
        return saveFailed
    }
}
