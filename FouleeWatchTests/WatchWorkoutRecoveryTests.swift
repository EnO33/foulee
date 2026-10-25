import FouleeKit
import Foundation
import Testing
@testable import FouleeWatch

/// Cover for #554: a session that outlived the app is picked up, never
/// finished behind the wearer's back.
@MainActor
@Suite("Watch session recovery")
struct WatchWorkoutRecoveryTests {
    private func metrics(of store: WatchWorkoutStore) -> WatchWorkoutMetrics? {
        guard case .active(let metrics) = store.state else { return nil }
        return metrics
    }

    @Test("Without a session left running, nothing happens")
    func nothingToRecover() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()

        await store.recover()

        #expect(store.state == .idle)
        #expect(stub.recoverCalls == 1)
        #expect(stub.startCalls == 0)
    }

    @Test("A session left running comes back on screen, its clock where it was")
    func sessionComesBack() async throws {
        let stub = WorkoutHealthKitStub()
        let clock = stub.clock
        // Twenty minutes in, one of them paused before the app died.
        let start = clock.now
        clock.advance(by: 1_200)
        stub.recoverable = RecoverableSession(activity: .running, startedAt: start, elapsed: 1_140)
        let store = stub.makeStore()

        await store.recover()

        let shown = try #require(metrics(of: store))
        #expect(shown.activity == .running)
        #expect(shown.elapsed == 1_140)
        #expect(!store.isPaused)
        #expect(stub.startCalls == 0)
        #expect(stub.endCalls == 0)
        #expect(stub.mirrorOffers == 1)
        // No stamp, no outing to read back.
        #expect(stub.savedLegsAsked.isEmpty)
    }

    @Test("The legs saved before the app died count in the outing")
    func earlierLegsCount() async throws {
        let stub = WorkoutHealthKitStub()
        let clock = stub.clock
        let outing = UUID()
        let walk = WatchWorkoutSegment(
            id: UUID(),
            activity: .walking,
            start: clock.now,
            end: clock.now.addingTimeInterval(600),
            steps: 1_000,
            distanceMeters: 800,
            activeCalories: 40
        )
        clock.advance(by: 900)
        stub.savedLegs = [walk]
        stub.recoverable = RecoverableSession(
            activity: .running,
            startedAt: try #require(walk.end),
            leg: OutingLeg(outingID: outing, index: 1),
            elapsed: 300
        )
        let store = stub.makeStore()

        await store.recover()

        let shown = try #require(metrics(of: store))
        #expect(stub.savedLegsAsked == [outing])
        #expect(shown.legs.count == 2)
        #expect(shown.legs.first?.id == walk.id)
        #expect(shown.elapsed == 900)
        #expect(shown.steps == 1_000)
    }

    @Test("A session paused when the app died comes back paused")
    func pausedSessionStaysPaused() async {
        let stub = WorkoutHealthKitStub()
        let clock = stub.clock
        let start = clock.now
        clock.advance(by: 600)
        stub.recoverable = RecoverableSession(activity: .walking, startedAt: start, elapsed: 300, isPaused: true)
        let store = stub.makeStore()

        await store.recover()
        clock.advance(by: 120)
        store.refreshActivityTotals(at: clock.now)

        #expect(store.isPaused)
        #expect(metrics(of: store)?.elapsed == 300)
    }

    @Test("Stopping a recovered outing saves its session")
    func recoveredSessionIsSaved() async {
        let stub = WorkoutHealthKitStub()
        let clock = stub.clock
        stub.recoverable = RecoverableSession(activity: .walking, startedAt: clock.now, elapsed: 0)
        let store = stub.makeStore()
        await store.recover()
        clock.advance(by: 600)

        await store.stop()

        #expect(stub.endCalls == 1)
        #expect(stub.finishCalls == 1)
        #expect(store.saveFailed == false)
    }

    @Test("A second launch signal recovers nothing more")
    func recoversOnce() async {
        let stub = WorkoutHealthKitStub()
        stub.recoverable = RecoverableSession(activity: .walking, startedAt: stub.clock.now, elapsed: 0)
        let store = stub.makeStore()

        await store.recover()
        await store.recover()

        #expect(stub.recoverCalls == 1)
        #expect(stub.mirrorOffers == 1)
    }
}

private extension WatchWorkoutStore {
    /// `nil` until the outing has ended.
    var saveFailed: Bool? {
        guard case .ended(_, let saveFailed) = state else { return nil }
        return saveFailed
    }
}
