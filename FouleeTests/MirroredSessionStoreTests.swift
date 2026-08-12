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

    private func snapshot(
        at offset: TimeInterval,
        outingAt outing: TimeInterval = 0,
        activity: SessionActivity = .walking,
        steps: Int = 0,
        isEnded: Bool = false
    ) -> MirroredSessionEvent {
        .snapshot(
            WatchSessionSnapshot(
                sentAt: base.addingTimeInterval(offset),
                outingStartedAt: base.addingTimeInterval(outing),
                activity: activity,
                steps: steps,
                distanceMeters: 0,
                activeCalories: 0,
                heartRate: nil,
                isEnded: isEnded
            )
        )
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

    // MARK: - The figures (issue #278)

    @Test("A session known but not yet measured shows no figures")
    func figuresCanLagTheSession() {
        let store = store()
        store.apply(mirror(.walking, at: 0))

        #expect(store.isMirroring)
        #expect(store.figures == nil, "zeros would look measured; nothing is honest")
    }

    /// HealthKit hands over everything that accumulated since the last wake and
    /// promises delivery, not sequence. A stale batch must not rewind the
    /// counters on screen.
    @Test("A snapshot older than the one held is dropped")
    func theNewestWins() {
        let store = store()
        store.apply(snapshot(at: 60, steps: 500))
        store.apply(snapshot(at: 30, steps: 200))

        #expect(store.figures?.steps == 500)
    }

    @Test("A newer snapshot replaces the figures")
    func aNewerSnapshotWins() {
        let store = store()
        store.apply(snapshot(at: 30, steps: 200))
        store.apply(snapshot(at: 60, steps: 500))

        #expect(store.figures?.steps == 500)
    }

    /// Figures can arrive before — or instead of — the mirror that should have
    /// announced the session. Showing nothing while the wrist is plainly
    /// recording would be worse than believing them.
    @Test("Figures alone are enough to know a session is running")
    func figuresImplyASession() {
        let store = store()
        store.apply(snapshot(at: 30, activity: .running))

        #expect(store.isMirroring)
        #expect(store.session?.activity == .running)
    }

    /// The wrist saying so is the end. An `HKWorkoutType` observer would fire
    /// on every `finishWorkout()` since issue #265 — it would announce the end
    /// of the outing at the first walk→run switch.
    @Test("A snapshot marked ended clears everything")
    func isEndedEndsIt() {
        let store = store()
        store.apply(mirror(.walking, at: 0))
        store.apply(snapshot(at: 60, steps: 500))
        store.apply(snapshot(at: 90, steps: 600, isEnded: true))

        #expect(store.isMirroring == false)
        #expect(store.figures == nil)
        #expect(store.outingStartedAt == nil)
    }

    /// The sport is the one thing a snapshot restates that the mirror also
    /// carries, and the snapshot is the fresher of the two.
    @Test("A snapshot updates the sport being done")
    func theSportFollowsTheFigures() {
        let store = store()
        store.apply(mirror(.walking, at: 0))
        store.apply(snapshot(at: 60, activity: .running))

        #expect(store.session?.activity == .running)
    }

    /// **The bug three independent reviewers found before this test existed.**
    ///
    /// HealthKit delivers in *batches*, so several snapshots are routinely in
    /// flight at once. Clearing the figures at the end of an outing used to
    /// clear the « newest wins » bound with them — so the first stale snapshot
    /// to land afterwards was accepted, and put a finished session back on
    /// screen with figures from before the end.
    @Test("A stale snapshot arriving after the end does not resurrect the session")
    func aLateSnapshotCannotResurrect() {
        let store = store()
        store.apply(snapshot(at: 60, steps: 500))
        store.apply(snapshot(at: 90, steps: 600, isEnded: true))
        #expect(store.isMirroring == false)

        // Sent before the end, delivered after it.
        store.apply(snapshot(at: 75, steps: 550))

        #expect(store.isMirroring == false)
        #expect(store.figures == nil)
    }

    /// The bound is `>=`, not `>`: two snapshots stamped the same instant are
    /// the same statement, and the second says nothing new.
    @Test("A snapshot as old as the one held is dropped")
    func anEquallyOldSnapshotIsDropped() {
        let store = store()
        store.apply(snapshot(at: 60, steps: 500))
        store.apply(snapshot(at: 60, steps: 999))

        #expect(store.figures?.steps == 500)
    }

    /// The outing's clock comes from the wrist, which knows where the outing
    /// began across legs — not from the leg the phone happens to be mirroring.
    @Test("The figures carry the outing's start, and it wins")
    func theFiguresCarryTheOutingClock() {
        let store = store()
        store.apply(mirror(.walking, at: 600))
        store.apply(snapshot(at: 700, outingAt: 0))

        #expect(store.outingStartedAt == base, "the wrist knows where the outing began")
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
