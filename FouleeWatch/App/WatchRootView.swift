import SwiftUI

/// Owns the workout store and routes to home / active / ended screens.
struct WatchRootView: View {
    @State private var store = WatchWorkoutStore()
    @State private var todayStore = WatchTodayStore()
    /// « Les deux » only: the question is on screen and nothing has started.
    /// Local to the idle route — a session in flight clears it.
    @State private var isChoosingActivity = false
    private let pendingStart = WatchPendingStart.shared

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
                WatchSessionPager(
                    metrics: metrics,
                    today: todayStore,
                    onStop: { Task { await store.stop() } }
                )
            case .ended(let metrics, let saveFailed):
                WatchFinishedView(
                    metrics: metrics,
                    saveFailed: saveFailed,
                    // The one sentence that explains a failure, shown where the
                    // failure is (issue #256). It used to reach only the home
                    // screen, which `reset()` clears on the way there.
                    errorMessage: store.lastError,
                    onRetry: { Task { await store.retrySave() } },
                    onDone: { store.reset() }
                )
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.state)
        .animation(.easeOut(duration: 0.25), value: isChoosingActivity)
        .task { await WatchWaterBackgroundDelivery.start() }
        // A start asked for by the phone (issue #283). Drained on appear *and*
        // watched, because both orders happen: the request may have launched
        // this app, or landed while it was already on screen.
        .task { startIfPhoneAsked() }
        .onChange(of: pendingStart.activity) { _, _ in startIfPhoneAsked() }
    }

    /// Start what the phone asked for, if anything, and if nothing is running.
    ///
    /// The guard is not politeness: the phone can ask while a session is
    /// already in flight — `startWatchApp` does not know what the wrist is
    /// doing — and starting a second one would strand the first.
    private func startIfPhoneAsked() {
        guard case .idle = store.state, let activity = pendingStart.take() else { return }
        begin(activity)
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
