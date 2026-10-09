import Clocks
import Dependencies
import Foundation
import Testing
@testable import Foulee

/// Carrying a phone walk on at the wrist (issue #335): the phone saves its
/// stretch as the outing's first leg and tells the wrist how to go on.
@Suite("ActiveWalkStore handoff")
@MainActor
struct ActiveWalkStoreHandoffTests {
    private let frozen = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Boom: Error {}

    /// Everything the store hands to the outside world, recorded.
    private final class Recorder: Sendable {
        let saved = LockedRef<WalkSession?>(nil)
        let phoneSessions = LockedRef<[PhoneSessionStatus?]>([])
        let handoffs = LockedRef<[SessionHandoff]>([])
        let wokenFor = LockedRef<[SessionActivity]>([])
    }

    private func withStore(
        watchRefuses: Bool = false,
        _ body: (ActiveWalkStore, Recorder) async throws -> Void
    ) async throws {
        let recorder = Recorder()
        try await withDependencies {
            $0.date = .constant(frozen)
            $0.pedometer = .testValue
            $0.continuousClock = TestClock()
            $0.healthKit = HealthKitClient(
                requestAuthorization: { true },
                todayMetrics: { .zero },
                saveWorkout: { recorder.saved.set($0) },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { WorkoutDetail(summary: $0, heartRateSamples: [], stepsCount: 0) }
            )
            $0.watchHandoff = WatchHandoffClient(
                publishPhoneSession: { recorder.phoneSessions.set(recorder.phoneSessions.value + [$0]) },
                publishHandoff: { recorder.handoffs.set(recorder.handoffs.value + [$0]) }
            )
            $0.mirroredWorkout = MirroredWorkoutClient(
                events: { AsyncStream { $0.finish() } },
                send: { _ in },
                startWatchSession: { activity in
                    if watchRefuses { throw Boom() }
                    recorder.wokenFor.set(recorder.wokenFor.value + [activity])
                },
                isWatchAppInstalled: { true }
            )
        } operation: {
            try await body(ActiveWalkStore(), recorder)
        }
    }

    // MARK: - What the wrist is told

    @Test("A walk in progress is announced to the wrist, and withdrawn when it ends")
    func theWalkIsAnnounced() async throws {
        try await withStore { store, recorder in
            store.start(activity: .running)
            #expect(recorder.phoneSessions.value == [PhoneSessionStatus(startedAt: frozen)])
            #expect(ActiveWalkStore.current === store)

            await store.stop()
            #expect(recorder.phoneSessions.value == [PhoneSessionStatus(startedAt: frozen), nil])
            #expect(ActiveWalkStore.current !== store)
        }
    }

    @Test("A walk discarded without saving is withdrawn too")
    func aResetWithdraws() async throws {
        try await withStore { store, recorder in
            store.start()
            store.reset()
            #expect(recorder.phoneSessions.value.last == .some(nil))
            #expect(ActiveWalkStore.current !== store)
        }
    }

    // MARK: - Handing over

    @Test("Handing over saves the walk as the outing's first leg")
    func theWalkIsSavedAsLegZero() async throws {
        try await withStore { store, recorder in
            store.start(activity: .running)
            let handoff = try #require(await store.handOff())

            #expect(recorder.saved.value?.outing == OutingLeg(outingID: handoff.outingID, index: 0))
            #expect(handoff.phoneLeg.activity == .running)
            #expect(handoff.phoneLeg.start == frozen)
            #expect(handoff.handedOverAt == frozen)
            #expect(handoff.continuingLeg.index == 1)
        }
    }

    @Test("A paused walk can be handed over too")
    func aPausedWalkHandsOver() async throws {
        try await withStore { store, _ in
            store.start()
            await store.pause()
            #expect(await store.handOff() != nil)
        }
    }

    @Test("There is nothing to hand over without a walk")
    func nothingToHandOver() async throws {
        try await withStore { store, recorder in
            #expect(await store.handOff() == nil)
            #expect(recorder.saved.value == nil)
        }
    }

    /// A walk that simply ends on the phone is not part of any outing.
    @Test("A plain stop stamps no outing")
    func aPlainStopIsNotAnOuting() async throws {
        try await withStore { store, recorder in
            store.start()
            await store.stop()
            #expect(recorder.saved.value?.outing == nil)
        }
    }

    // MARK: - « Continuer sur ma Watch »

    @Test("Continuing on the watch hands over first, then wakes the watch")
    func continuingOnTheWatch() async throws {
        try await withStore { store, recorder in
            store.start(activity: .running)
            await store.handOffToWatch()

            #expect(recorder.handoffs.value.count == 1)
            #expect(recorder.wokenFor.value == [.running])
            #expect(recorder.handoffs.value.first?.outingID == recorder.saved.value?.outing?.outingID)
            #expect(store.lastError == nil)
        }
    }

    /// The phone's leg is saved either way; a watch that does not answer is
    /// said on screen, not left to guess.
    @Test("A watch that will not wake is said on screen")
    func aWatchThatWillNotWake() async throws {
        try await withStore(watchRefuses: true) { store, recorder in
            store.start()
            await store.handOffToWatch()

            #expect(recorder.saved.value != nil)
            #expect(store.lastError != nil)
        }
    }
}
