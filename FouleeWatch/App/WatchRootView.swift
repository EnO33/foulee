import SwiftUI

/// Owns the workout store and routes to home / active / ended screens.
struct WatchRootView: View {
    @State private var store = WatchWorkoutStore()
    @State private var todayStore = WatchTodayStore()
    /// « Les deux » only: the question is on screen and nothing has started.
    /// Local to the idle route — a session in flight clears it.
    @State private var isChoosingActivity = false

    var body: some View {
        Group {
            switch store.state {
            case .idle:
                WatchIdleScreen(
                    today: todayStore,
                    errorMessage: store.lastError,
                    isChoosingActivity: isChoosingActivity,
                    onStart: begin,
                    onAsk: { isChoosingActivity = true },
                    onCancel: { isChoosingActivity = false }
                )
            case .active(let metrics):
                WatchActiveWalkView(
                    metrics: metrics,
                    onStop: { Task { await store.stop() } }
                )
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
        .animation(.easeOut(duration: 0.25), value: isChoosingActivity)
        .task { await WatchWaterBackgroundDelivery.start() }
    }

    /// One place a session begins, whether the activity came from the synced
    /// mode or from the user answering the question.
    private func begin(_ activity: SessionActivity) {
        isChoosingActivity = false
        Task { await store.start(activity: activity) }
    }

    /// What a tap on « Démarrer » resolves to, given the mode the phone synced
    /// (issues #223, #224).
    ///
    /// Read at tap time, not at view build: the phone can push a new mode while
    /// this screen sits on the wrist, and the stamp is permanent. A watch that
    /// has never received a payload — a fresh pairing, or a phone that hasn't
    /// been opened since the update — falls back to walking, the app's
    /// historical behaviour, rather than asking a question the user has never
    /// been shown the settings for.
    ///
    /// Static, internal, and taking the defaults suite rather than reading the
    /// shared one inline: this is the watch's whole half of the phone→wrist
    /// wire, and inside a `View` body nothing could assert it. The parameter is
    /// `WatchSyncStore`'s own test seam, so a test drives the real write → read
    /// → resolve path against a throwaway suite.
    static func startIntent(
        syncedTo defaults: UserDefaults = WatchSyncStore.sharedDefaults
    ) -> ActivityStartIntent {
        ActivityStartIntent(mode: WatchSyncStore.read(from: defaults)?.activityMode ?? .walking)
    }
}
