import SwiftUI

/// Owns the workout store and routes to home / active / ended screens.
struct WatchRootView: View {
    @State private var store = WatchWorkoutStore()
    @State private var todayStore = WatchTodayStore()

    var body: some View {
        Group {
            switch store.state {
            case .idle:
                WatchTodayView(store: todayStore, errorMessage: store.lastError) {
                    Task { await store.start(activity: Self.startActivity()) }
                }
            case .active(let metrics):
                WatchActiveWalkView(metrics: metrics) {
                    Task { await store.stop() }
                }
            case .ended(let metrics, let saveFailed):
                WatchFinishedView(
                    metrics: metrics,
                    saveFailed: saveFailed,
                    onRetry: { Task { await store.retrySave() } },
                    onDone: { store.reset() }
                )
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.state)
        .task { await WatchWaterBackgroundDelivery.start() }
    }

    /// What Santé will record the session the user is starting as (issue #223).
    ///
    /// Read at tap time, not at view build: the phone can push a new mode while
    /// this screen sits on the wrist, and the stamp is permanent. A watch that
    /// has never received a payload — a fresh pairing, or a phone that hasn't
    /// been opened since the update — falls back to walking, the app's
    /// historical behaviour.
    ///
    /// Static, internal, and taking the defaults suite rather than reading the
    /// shared one inline: this is the watch's whole half of the phone→wrist
    /// wire, and inside a `View` body nothing could assert it. The parameter is
    /// `WatchSyncStore`'s own test seam, so a test drives the real write → read
    /// → resolve path against a throwaway suite.
    static func startActivity(
        syncedTo defaults: UserDefaults = WatchSyncStore.sharedDefaults
    ) -> SessionActivity {
        SessionActivity(mode: WatchSyncStore.read(from: defaults)?.activityMode ?? .walking)
    }
}
