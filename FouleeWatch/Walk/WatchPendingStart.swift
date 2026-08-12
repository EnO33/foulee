import Observation

/// A session the phone asked for, waiting for something able to start it
/// (issue #283).
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

    private(set) var activity: SessionActivity?

    func request(_ activity: SessionActivity) {
        self.activity = activity
    }

    /// Read and clear. Taking rather than observing-and-resetting is what stops
    /// a second start when the view rebuilds for an unrelated reason.
    func take() -> SessionActivity? {
        defer { activity = nil }
        return activity
    }
}
