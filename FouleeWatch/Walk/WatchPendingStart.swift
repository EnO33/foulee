import FouleeKit
import Observation

/// A session the phone or Siri asked for, waiting for something able to start
/// it (issues #283, #607).
///
/// `HKHealthStore.startWatchApp(with:)` wakes the watch app and hands the
/// configuration to `WKApplicationDelegate`, which exists before any view does
/// and cannot reach `WatchWorkoutStore` — the store is `@State` inside
/// `WatchRootView`. This is the one hop between them.
///
/// Observable rather than a plain box because the two orders both happen: the
/// app may be launched *by* the request (the view appears afterwards and drains
/// it) or already be on screen (the view is told). Draining on appear alone
/// would lose the second case, which is the one where the wearer is looking at
/// the watch.
@MainActor
@Observable
final class WatchPendingStart {
    static let shared = WatchPendingStart()

    /// `.ask` only from Siri: the phone always names a sport, but « Commencer
    /// une sortie » follows the synced mode, and « les deux » asks on the
    /// wrist exactly as « Démarrer » does.
    private(set) var intent: ActivityStartIntent?

    func request(_ intent: ActivityStartIntent) {
        self.intent = intent
    }

    /// Read and clear. Taking rather than observing-and-resetting is what stops
    /// a second start when the view rebuilds for an unrelated reason.
    func take() -> ActivityStartIntent? {
        defer { intent = nil }
        return intent
    }
}
