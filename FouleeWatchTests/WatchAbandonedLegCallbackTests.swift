import Foundation
import Testing
@testable import FouleeWatch

/// Callbacks from a leg the store has already closed (issue #290).
///
/// Since issue #265 an outing opens one `HKWorkoutSession` per leg, and the
/// store is the delegate of every one of them. HealthKit hands a delegate the
/// object that is calling and nothing else, so « which leg is this about? » has
/// to be asked on every callback — and it was not.
///
/// It cost a real sortie. `HKError.errorAnotherWorkoutSessionStarted` is
/// delivered to the session that has just been *superseded*, so opening the
/// second leg makes the first fail **by design**. Foulée read that expected
/// failure as the death of the outing and ended it, on the second switch, on a
/// wrist, outdoors.
@MainActor
@Suite("Callbacks from an abandoned leg")
struct WatchAbandonedLegCallbackTests {
    private let base = Date()

    private func estimate(_ activity: SessionActivity, at offset: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(
            startDate: base.addingTimeInterval(offset),
            walking: activity == .walking,
            running: activity == .running
        )
    }

    /// A walk that became a run, cut at the boundary — two legs, so there is a
    /// closed one to impersonate.
    private func splitOuting(
        _ stub: WorkoutHealthKitStub
    ) async -> WatchWorkoutStore {
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }
        motion.deliver(estimate(.running, at: 60))
        await waitUntil {
            guard case .active(let metrics) = store.state else { return false }
            return metrics.activity == .running
        }
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))
        #expect(stub.startedLegs.count == 2)
        return store
    }

    private func isActive(_ store: WatchWorkoutStore) -> Bool {
        if case .active = store.state { return true }
        return false
    }

    // MARK: - The failure that ended a real outing

    @Test("A failure from the leg just closed does not end the outing")
    func theSupersededLegIsIgnored() async {
        let stub = WorkoutHealthKitStub()
        let store = await splitOuting(stub)

        // What HealthKit does the moment the second leg opens.
        store.handleSessionFailure(
            "another session is starting",
            from: stub.handleIDs[0]
        )

        #expect(isActive(store), "the outing must survive its own leg being superseded")
        #expect(store.lastError == nil, "an expected failure must not reach the screen")
    }

    @Test("A failure from the leg in flight still ends the outing")
    func theCurrentLegStillFails() async {
        let stub = WorkoutHealthKitStub()
        let store = await splitOuting(stub)

        store.handleSessionFailure("session interrompue", from: stub.handleIDs[1])

        #expect(isActive(store) == false)
        #expect(store.lastError == "session interrompue")
    }

    /// The path a test drives, and any failure that belongs to no session.
    @Test("An unattributed failure is still treated as the outing's")
    func anUnnamedFailureIsAccepted() async {
        let stub = WorkoutHealthKitStub()
        let store = await splitOuting(stub)

        store.handleSessionFailure("boom")

        #expect(isActive(store) == false)
        #expect(store.lastError == "boom")
    }

    // MARK: - The mirror never costs a sortie

    /// Issue #277. A phone that is off, unpaired or out of range refuses the
    /// mirror, and that must be invisible to the wrist: the walk is being
    /// measured perfectly well without it.
    @Test("A refused mirror leaves the outing recording")
    func aRefusedMirrorIsHarmless() async {
        let stub = WorkoutHealthKitStub()
        stub.mirrorError = StubError()
        let store = stub.makeStore()
        await store.start(activity: .walking)

        #expect(isActive(store))
        #expect(store.lastError == nil, "a phone problem must not reach the wrist")
        #expect(stub.mirrorOffers == 1)
    }

    /// Each leg is a session of its own, so each one has to be offered again —
    /// a mirror does not outlive the session it was opened on.
    @Test("Every leg is offered to the phone, not just the first")
    func everyLegIsOffered() async {
        let stub = WorkoutHealthKitStub()
        _ = await splitOuting(stub)

        #expect(stub.startedLegs.count == 2)
        #expect(stub.mirrorOffers == 2)
    }

    // MARK: - The same hole on the metrics path

    @Test("Only the leg in flight is recognised, session and builder alike")
    func identityIsPerLeg() async {
        let stub = WorkoutHealthKitStub()
        let store = await splitOuting(stub)

        #expect(store.isCurrentLeg(session: stub.handleIDs[1]))
        #expect(store.isCurrentLeg(builder: stub.handleIDs[1]))
        // The leg closed at the boundary — its last delivery must not write
        // into the counters that now stand for the new one.
        #expect(store.isCurrentLeg(session: stub.handleIDs[0]) == false)
        #expect(store.isCurrentLeg(builder: stub.handleIDs[0]) == false)
    }

    /// The predicate is asserted above; that `ingest` actually *calls* it is
    /// not, and cannot be: `ingest(builder:)` takes an `HKLiveWorkoutBuilder`,
    /// a type no test can construct. So the wiring is checked the way
    /// `WatchScreenshotModeTests` checks its guards — by reading the source.
    ///
    /// Not belt-and-braces. Deleting the guard from `ingest` leaves every other
    /// test in this suite passing: verified by doing it.
    @Test("The metrics path is wired to the same filter")
    func ingestIsFiltered() throws {
        let source = try Self.strippedSource(at: "FouleeWatch/Walk/WatchWorkoutStore.swift")
        let ingest = try #require(source.range(of: "func ingest(builder:"))
        let body = source[ingest.lowerBound...].prefix(400)
        #expect(body.contains("isCurrentLeg(builder: ObjectIdentifier(builder))"))
    }

    /// A source file with its comment lines dropped, so a scan matches code and
    /// not prose.
    private static func strippedSource(at path: String) throws -> String {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()   // FouleeWatchTests/
            .deletingLastPathComponent()   // repository root
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Between closing a leg and opening the next, `sessionHandle` is nil.
    /// Nothing may be accepted in that window either.
    @Test("With no session open, a named callback is refused")
    func nothingIsCurrentWithoutASession() async {
        let stub = WorkoutHealthKitStub()
        let store = await splitOuting(stub)
        let closed = stub.handleIDs[1]
        await store.stop()

        #expect(store.isCurrentLeg(session: closed) == false)
        #expect(store.isCurrentLeg(builder: closed) == false)
    }
}
