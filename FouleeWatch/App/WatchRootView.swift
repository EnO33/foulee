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
                    Task { await store.start(activity: startActivity()) }
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
    private func startActivity() -> SessionActivity {
        SessionActivity(mode: WatchSyncStore.read()?.activityMode ?? .walking)
    }
}
