import Testing
@testable import FouleeWatch

/// The one hop between the phone's request and the store that can act on it
/// (issue #283).
///
/// `startWatchApp(with:)` hands a configuration to `WKApplicationDelegate`,
/// which exists before any view does and cannot reach `WatchWorkoutStore` — the
/// store is `@State` inside `WatchRootView`.
@MainActor
@Suite("Pending start from the phone")
struct WatchPendingStartTests {
    @Test("Nothing is pending until the phone asks")
    func idleByDefault() {
        let pending = WatchPendingStart()
        #expect(pending.activity == nil)
        #expect(pending.take() == nil)
    }

    @Test("A request is held until something takes it")
    func aRequestIsHeld() {
        let pending = WatchPendingStart()
        pending.request(.running)
        #expect(pending.activity == .running)
        #expect(pending.take() == .running)
    }

    /// Taking rather than observing-and-resetting is what stops a second
    /// session from opening when the view rebuilds for an unrelated reason.
    @Test("A request is honoured once, not on every rebuild")
    func aRequestIsTakenOnce() {
        let pending = WatchPendingStart()
        pending.request(.walking)

        #expect(pending.take() == .walking)
        #expect(pending.take() == nil)
        #expect(pending.activity == nil)
    }

    /// The phone can ask twice before the watch has looked. The wearer gets the
    /// later answer, not the earlier one.
    @Test("A second request replaces the first")
    func theLastRequestWins() {
        let pending = WatchPendingStart()
        pending.request(.walking)
        pending.request(.running)

        #expect(pending.take() == .running)
    }
}
