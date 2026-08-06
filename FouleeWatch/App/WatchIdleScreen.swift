import SwiftUI

/// The watch's idle route: the home screen, or the activity question when
/// « les deux » forces it (issue #224).
///
/// Split out of `WatchRootView` because this is where the decision is made,
/// and a decision inside a `View` body is unassertable — the same argument
/// that put `startActivity` on `WatchRootView` as a static function for #223.
/// Everything here is a plain `let` or closure, so a test builds the screen,
/// pulls `WatchTodayView` out of the tree and taps its real « Démarrer »
/// action, then checks whether it started or asked.
///
/// The question replaces the home rather than being presented over it as a
/// sheet, and that costs something real: cancelling rebuilds `WatchTodayView`
/// scrolled back to the top, so a « les deux » user who opened the picker by
/// mistake scrolls down to « Démarrer » again. It is still the better trade.
/// A `.sheet`/`.fullScreenCover` stores its content in a closure, which puts
/// the picker out of reach of `ViewTreeProbe` — and the probe is what makes
/// « choosing Course records a run » assertable at all; and on watchOS a modal
/// adds a title bar, taking exactly the vertical space the picker is short of
/// on a 40 mm screen.
struct WatchIdleScreen: View {
    let today: WatchTodayStore
    var errorMessage: String?
    /// Whether the question is currently on screen. Owned by `WatchRootView`,
    /// passed in rather than held here so the route is a function of its
    /// inputs and a test can build both halves.
    var isChoosingActivity: Bool
    /// The synced mode, resolved at tap time rather than at build: the phone
    /// can push a new mode while this screen sits on the wrist, and the stamp
    /// is permanent. Defaulted to the real read, overridden by tests.
    var intent: () -> ActivityStartIntent = { WatchRootView.startIntent() }
    /// Start now, with an activity nobody has to guess at.
    var onStart: (SessionActivity) -> Void
    /// Ask first — « les deux » only.
    var onAsk: () -> Void
    /// Backed out of the question without starting anything.
    var onCancel: () -> Void

    var body: some View {
        if isChoosingActivity {
            // The answer goes down the very same path as a one-gesture start,
            // so there is one place a session can begin, not two.
            WatchActivityChoiceView(onChoose: onStart, onCancel: onCancel)
        } else {
            WatchTodayView(store: today, errorMessage: errorMessage, onStart: start)
        }
    }

    private func start() {
        switch intent() {
        case .start(let activity): onStart(activity)
        case .ask: onAsk()
        }
    }
}
