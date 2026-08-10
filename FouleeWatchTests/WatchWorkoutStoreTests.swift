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

    private(set) var startCalls = 0
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
    /// What HealthKit would report for this session's segments. Set by the
    /// tests of issue #250; empty everywhere else, which is what a session with
    /// nothing measured yet looks like.
    var segments: [WatchWorkoutSegment] = []

    /// Weak by design: the only strong reference lives in the handle's
    /// closures, so `nil` here means the store let go of the handle.
    private(set) weak var handleToken: AnyObject?

    func makeStore(detection: WatchActivityDetection = WatchActivityDetection(source: .inert)) -> WatchWorkoutStore {
        WatchWorkoutStore(healthKit: WatchWorkoutHealthKit(
            isAvailable: { self.isAvailable },
            requestAuthorization: { toShare, read in
                self.requestedShareTypes = toShare
                self.requestedReadTypes = read
                if let error = self.authError { throw error }
            },
            startSession: { configuration, _ in
                self.startCalls += 1
                self.startedConfiguration = configuration
                if let error = self.startError { throw error }
                return self.makeHandle()
            }
        ), detection: detection)
    }

    private func makeHandle() -> WatchWorkoutSessionHandle {
        let token = NSObject()
        handleToken = token
        return WatchWorkoutSessionHandle(
            end: {
                _ = token
                self.endCalls += 1
            },
            endCollection: { date in
                self.endCollectionCalls += 1
                if let error = self.endCollectionError { throw error }
                self.collectionEndDate = date
            },
            finishWorkout: {
                self.finishCalls += 1
                if let error = self.finishError { throw error }
            },
            collectionEndDate: { self.collectionEndDate },
            segments: { self.segments }
        )
    }
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
        #expect(store.lastError == "HealthKit n'est pas disponible sur ce device.")
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
        #expect(store.state == .ended(.zero, saveFailed: false))
        #expect(store.lastError == nil)
        #expect(stub.endCalls == 1)
        #expect(stub.endCollectionCalls == 1)
        #expect(stub.finishCalls == 1)
        #expect(stub.handleToken == nil)
    }

    @Test("stop() with a failing save keeps the builder for a retry")
    func stopSaveFailureRetainsBuilder() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.finishError = StubError()
        await store.stop()
        #expect(store.state == .ended(.zero, saveFailed: true))
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
        #expect(store.state == .ended(.zero, saveFailed: false))
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
        #expect(store.state == .ended(.zero, saveFailed: true))
        #expect(stub.finishCalls == 0)
        stub.endCollectionError = nil
        await store.retrySave()
        #expect(stub.endCollectionCalls == 2)
        #expect(stub.finishCalls == 1)
        #expect(store.state == .ended(.zero, saveFailed: false))
    }

    @Test("A retry that fails again keeps the failed state and the builder")
    func retrySaveFailureStaysFailed() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.finishError = StubError()
        await store.stop()
        await store.retrySave()
        #expect(store.state == .ended(.zero, saveFailed: true))
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
        #expect(store.state == .ended(.zero, saveFailed: false))
    }

    @Test("A session failure mid-walk lands on the failed summary, retryable")
    func sessionFailureMidWalk() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        store.handleSessionFailure("session interrompue")
        #expect(store.state == .ended(.zero, saveFailed: true))
        #expect(store.lastError == "session interrompue")
        #expect(stub.handleToken != nil)
        // "Réessayer" can still end collection and save the walk.
        await store.retrySave()
        #expect(store.state == .ended(.zero, saveFailed: false))
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
