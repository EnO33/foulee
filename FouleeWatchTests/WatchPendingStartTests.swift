import Testing
@testable import FouleeWatch

/// The one hop between the phone's or Siri's request and the store that can
/// act on it (issues #283, #607).
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
        #expect(pending.intent == nil)
        #expect(pending.take() == nil)
    }

    @Test("A request is held until something takes it")
    func aRequestIsHeld() {
        let pending = WatchPendingStart()
        pending.request(.start(.running))
        #expect(pending.intent == .start(.running))
        #expect(pending.take() == .start(.running))
    }

    /// Taking rather than observing-and-resetting is what stops a second
    /// session from opening when the view rebuilds for an unrelated reason.
    @Test("A request is honoured once, not on every rebuild")
    func aRequestIsTakenOnce() {
        let pending = WatchPendingStart()
        pending.request(.start(.walking))

        #expect(pending.take() == .start(.walking))
        #expect(pending.take() == nil)
        #expect(pending.intent == nil)
    }

    /// The phone can ask twice before the watch has looked. The wearer gets the
    /// later answer, not the earlier one.
    @Test("A second request replaces the first")
    func theLastRequestWins() {
        let pending = WatchPendingStart()
        pending.request(.start(.walking))
        pending.request(.start(.running))

        #expect(pending.take() == .start(.running))
    }

    /// Siri's « Commencer une sortie » for a « les deux » user: the question,
    /// held like a start, so the wrist asks rather than guessing a sport.
    @Test("A request to ask is held like a start")
    func anAskIsHeld() {
        let pending = WatchPendingStart()
        pending.request(.ask)

        #expect(pending.take() == .ask)
        #expect(pending.take() == nil)
    }
}
