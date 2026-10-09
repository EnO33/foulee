import Clocks
import Dependencies
import Foundation
import Testing
@testable import Foulee

/// The phone's session, shown and steered from the wrist (issue #342): the
/// phone stays the only recorder and tells the wrist where it stands.
@Suite("ActiveWalkStore on the wrist")
@MainActor
struct ActiveWalkStoreWatchTests {
    private let frozen = Date(timeIntervalSince1970: 1_700_000_000)

    private func withStore(_ body: (ActiveWalkStore, LockedRef<[PhoneSessionSnapshot?]>) async throws -> Void) async throws {
        let told = LockedRef<[PhoneSessionSnapshot?]>([])
        try await withDependencies {
            $0.date = .constant(frozen)
            $0.pedometer = .testValue
            $0.healthKit = .testValue
            $0.continuousClock = TestClock()
            $0.watchLive = WatchLiveClient { told.set(told.value + [$0]) }
        } operation: {
            try await body(ActiveWalkStore(), told)
        }
    }

    // MARK: - What the wrist is told

    @Test("Every change of phase is told at once")
    func phasesAreTold() async throws {
        try await withStore { store, told in
            store.start(activity: .running)
            await store.pause()
            store.resume()
            await store.stop()

            #expect(told.value.map { $0?.phase } == [.active, .paused, .active, .ended])
            #expect(told.value.first??.activity == .running)
            #expect(told.value.first??.sentAt == frozen)
        }
    }

    /// The wrist hides it on « ended » already; « no session » is what lets the
    /// context forget it.
    @Test("A session put away is withdrawn")
    func resetWithdraws() async throws {
        try await withStore { store, told in
            store.start()
            await store.stop()
            store.reset()
            #expect(told.value.last == .some(nil))
            #expect(ActiveWalkStore.current !== store)
        }
    }

    /// Ticks come every second; the wrist needs news every few.
    @Test("A session in flight is retold only once the interval has passed")
    func retellingIsPaced() async throws {
        try await withStore { store, told in
            store.start()
            store.tellWatchIfDue()
            #expect(told.value.count == 1)
        }
    }

    @Test("The figures are the session's own")
    func figures() async throws {
        try await withStore { store, _ in
            store.start(activity: .running)
            await store.pause()
            let snapshot = try #require(store.watchSnapshot(at: frozen))
            #expect(snapshot.phase == .paused)
            #expect(snapshot.timerBasis == nil)
            #expect(snapshot.steps == 0)
            #expect(snapshot.route.allSatisfy { $0.activity == .running })
        }
    }

    @Test("Nothing to tell without a session")
    func idleIsNothing() async throws {
        try await withStore { store, told in
            #expect(store.watchSnapshot(at: frozen) == nil)
            store.reset()
            #expect(told.value.isEmpty)
        }
    }

    // MARK: - Commands from the wrist

    @Test("The wrist can pause, resume and stop the session")
    func commandsAreCarriedOut() async throws {
        try await withStore { store, _ in
            store.start()
            #expect(ActiveWalkStore.current === store)

            #expect(await store.perform(.pause))
            guard case .paused = store.state else { Issue.record("expected paused"); return }

            #expect(await store.perform(.resume))
            guard case .active = store.state else { Issue.record("expected active"); return }

            #expect(await store.perform(.stop))
            guard case .finished = store.state else { Issue.record("expected finished"); return }
        }
    }

    /// The tap and the phone's own button can cross: the late one must not
    /// pretend it did something.
    @Test("A command the session is not in a state to obey is refused")
    func staleCommandsAreRefused() async throws {
        try await withStore { store, _ in
            #expect(await store.perform(.stop) == false)
            store.start()
            #expect(await store.perform(.resume) == false)
            await store.stop()
            #expect(await store.perform(.pause) == false)
        }
    }
}
