import Dependencies
import Foundation
import Testing
@testable import Foulee

/// What the phone makes of the mirrors the Watch offers (issue #277).
///
/// The HealthKit half — `workoutSessionMirroringStartHandler`, the delegate,
/// the session that has to be held alive — needs a real watch paired to a real
/// phone and is exercised by nothing here. What *is* testable is the half that
/// decides what the phone believes, and every rule below has a way of being
/// wrong that would show up as a bad screen mid-outing.
@MainActor
@Suite("Mirrored session store")
struct MirroredSessionStoreTests {
    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    private func mirror(_ activity: SessionActivity, at offset: TimeInterval) -> MirroredSessionEvent {
        .started(MirroredSession(startedAt: base.addingTimeInterval(offset), activity: activity))
    }

    private func store() -> MirroredSessionStore {
        withDependencies {
            $0.mirroredWorkout = .testValue
        } operation: {
            MirroredSessionStore()
        }
    }

    @Test("Nothing is mirrored until the wrist says so")
    func idleByDefault() {
        let store = store()
        #expect(store.session == nil)
        #expect(store.isMirroring == false)
        #expect(store.outingStartedAt == nil)
    }

    @Test("A mirror names the sport and starts the outing's clock")
    func aMirrorStartsTheOuting() {
        let store = store()
        store.apply(mirror(.walking, at: 0))

        #expect(store.isMirroring)
        #expect(store.session?.activity == .walking)
        #expect(store.outingStartedAt == base)
    }

    /// The rule that matters most, and the one easiest to get wrong: since
    /// issue #265 a change of sport closes one session and opens another, so
    /// the phone sees a **new mirror** mid-outing. Reading the outing's clock
    /// off the leg would reset it to zero every time the wearer broke into a
    /// run.
    @Test("A change of sport replaces the leg but not the outing's clock")
    func aSwitchKeepsTheOutingClock() {
        let store = store()
        store.apply(mirror(.walking, at: 0))
        store.apply(mirror(.running, at: 600))

        #expect(store.session?.activity == .running)
        #expect(store.session?.startedAt == base.addingTimeInterval(600))
        #expect(store.outingStartedAt == base, "the outing did not restart, only the leg did")
    }

    @Test("The end of the outing clears both")
    func endingClearsEverything() {
        let store = store()
        store.apply(mirror(.walking, at: 0))
        store.apply(.ended)

        #expect(store.session == nil)
        #expect(store.isMirroring == false)
        #expect(store.outingStartedAt == nil)
    }

    /// A wrist that starts again after stopping is a new outing, with its own
    /// clock — not a resumption of the old one.
    @Test("A fresh outing after an end starts its clock again")
    func aNewOutingStartsAfresh() {
        let store = store()
        store.apply(mirror(.walking, at: 0))
        store.apply(.ended)
        store.apply(mirror(.walking, at: 3_600))

        #expect(store.outingStartedAt == base.addingTimeInterval(3_600))
    }
}
