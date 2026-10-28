import FouleeKit
import SwiftUI

/// Owns the workout store and routes to home / active / ended screens.
struct WatchRootView: View {
    @State private var store = WatchWorkoutStore()
    @State private var todayStore = WatchTodayStore()
    /// « Les deux » only: the question is on screen and nothing has started.
    /// Local to the idle route — a session in flight clears it.
    @State private var isChoosingActivity = false
    private let pendingStart = WatchPendingStart.shared
    /// A session that outlived the app, to pick up (issue #554).
    private let recovery = WatchWorkoutRecovery.shared
    /// The phone's session in flight, shown while the wrist records nothing
    /// itself (issue #342).
    private let phoneSession = WatchPhoneSession.shared

    var body: some View {
        Group {
            switch store.state {
            case .idle:
                if let snapshot = phoneSession.shown(at: .now) {
                    WatchPhoneSessionPager(
                        snapshot: snapshot,
                        isSending: phoneSession.isSending,
                        errorMessage: phoneSession.errorMessage,
                        onCommand: { command in Task { await phoneSession.send(command) } }
                    )
                } else {
                    idleScreen
                }
            case .active(let metrics):
                WatchSessionPager(
                    metrics: metrics,
                    today: todayStore,
                    route: store.route,
                    errorMessage: store.lastError,
                    isSaving: store.isSaving,
                    onTogglePause: { store.isPaused ? store.resume() : store.pause() },
                    onStop: { Task { await store.stop() } }
                )
            case .ended(let metrics, let saveFailed):
                WatchFinishedView(
                    metrics: metrics,
                    route: WatchRoutePortion.portions(
                        of: store.route.locations,
                        legs: metrics.legs,
                        current: nil
                    ),
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
        // A session that outlived the app first (issue #554): a start the
        // phone asked for must not open a second one beside it. Then a start
        // asked for by the phone (issue #283) or by Siri (#607), drained on
        // appear *and* watched, because both orders happen: the request may
        // have launched this app, or landed while it was already on screen.
        .task {
            await store.recover()
            startIfAsked()
        }
        .onChange(of: recovery.requests) { _, _ in Task { await store.recover() } }
        .onChange(of: pendingStart.intent) { _, _ in startIfAsked() }
    }

    /// Home, with nothing in flight here or on the phone.
    private var idleScreen: some View {
        WatchIdleScreen(
            today: todayStore,
            errorMessage: store.lastError,
            isChoosingActivity: isChoosingActivity,
            onStart: begin,
            onAsk: { isChoosingActivity = true },
            onCancel: { isChoosingActivity = false }
        )
    }

    /// Start what the phone or Siri asked for, if anything, and if nothing is
    /// running.
    ///
    /// The guard is not politeness: the phone can ask while a session is
    /// already in flight — `startWatchApp` does not know what the wrist is
    /// doing — and starting a second one would strand the first. A phone
    /// outing on the wrist wins too: its mirror stays, as the phone's own
    /// shortcut opens the watch's mirror (#604). The request is taken either
    /// way, so a refused one does not start a session later, on some
    /// unrelated relaunch.
    private func startIfAsked() {
        let intent = pendingStart.take()
        guard case .idle = store.state, phoneSession.shown(at: .now) == nil, let intent else { return }
        switch intent {
        case .start(let activity): begin(activity)
        case .ask: isChoosingActivity = true
        }
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
