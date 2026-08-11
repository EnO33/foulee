import SwiftUI

/// The pages of a live session, in the order the crown walks them (issue #274).
///
/// Selection binds to **these cases, never to an index**: the set is already
/// about to grow (« Jambes » in #276, « Journée » in #280, « Hydratation » in
/// #281) and « Jambes » only appears once an outing has changed sport, so the
/// position of everything after it moves at runtime.
///
/// « Contrôles » sits immediately under « Séance » rather than above it, which
/// is where the epic first put it. The reason is muscle memory: until this
/// change the whole session lived in one scroll view and « Arrêter » was at the
/// bottom of it, so *scroll down to stop* is the gesture people already have.
/// The pages added later go below « Contrôles », so stopping stays one gesture
/// from the default however many pages arrive.
enum WatchSessionPage: Hashable {
    case session
    case controls
}

/// Live session screen, split into pages (issue #274).
///
/// **The split is a layout fix before it is a feature.** Laid out as one column
/// this content needs about 225 pt; a 40 mm watch offers roughly 170 pt of safe
/// area, and the overflow was measured rather than guessed: on a 46 mm the stop
/// button's capsule ran ~13 pt past the bottom edge, and on a 40 mm SE the
/// button was off screen entirely — label and all — so **a session could not be
/// stopped from this screen** (issue #241). The same overflow pushed the 38 pt
/// clock up into the corner watchOS draws its own time in, where the two
/// overprinted each other.
///
/// Issue #241 answered that with a scroll view, which kept everything reachable
/// but left the screen you read *while moving* requiring a scroll. Moving the
/// button to its own page is what buys that back.
///
/// **Moving the button was not, on its own, enough** — and the paper estimate
/// that said it would be (« ~150 pt, fits on a 40 mm ») was wrong twice over. A
/// `.verticalPage` `TabView` keeps noticeably more room above its content than
/// a plain scroll view, so the first capture of the paged screen still cut
/// « kcal » and « bpm » off the bottom of a **46 mm** — the roomiest watch in
/// the set. What actually made it fit was measuring the board and then cutting:
/// two-line metric tiles instead of three, a 34 pt clock instead of 38, tighter
/// spacing, and no `Divider()`. Verified on a 40 mm SE probe, at default text
/// size, with room to spare.
///
/// The pages keep their scroll views for the largest Dynamic Type sizes, where
/// nothing fits on any wrist.
///
/// **One vertical axis, no horizontal one.** Apple's Workout app spends its
/// horizontal axis on Now Playing, which Foulée does not have, and nesting two
/// `TabView`s is not documented behaviour to build on.
///
/// **No `navigationTitle`.** There is no `NavigationStack` here on purpose — a
/// swipe-back gesture and a paging gesture on the same view is a conflict this
/// screen does not need — and `navigationTitle` renders nothing without one.
/// Neither page carries a drawn header either: a 34 pt clock and a button
/// reading « Arrêter » say what they are, and a header line would cost 14–18 pt
/// of the very budget this change exists to recover. VoiceOver gets the naming
/// instead, through `accessibilityLabel` on each page, which costs no pixels.
/// The pages of #276/#280/#281 show figures that *are* ambiguous unlabelled —
/// that is when a drawn header earns its height, not before.
struct WatchSessionPager: View {
    let metrics: WatchWorkoutMetrics
    var onStop: () -> Void

    @State private var page: WatchSessionPage = .session

    var body: some View {
        TabView(selection: $page) {
            WatchSessionMetricsPage(metrics: metrics)
                .tag(WatchSessionPage.session)
            WatchSessionControlsPage(metrics: metrics, onStop: onStop)
                .tag(WatchSessionPage.controls)
        }
        .tabViewStyle(.verticalPage(transitionStyle: .identity))
    }
}

/// The elapsed clock, and the only thing on any page that has to redraw every
/// second.
///
/// The `TimelineView` is **here, around a single `Text`**, and not around the
/// pager. Wrapping the pager would rebuild the whole `TabView` — both pages and
/// the selection binding — once a second in order to move four digits.
///
/// `context.date`, never `metrics.elapsed`: that was the whole of issue #266.
/// The timeline rebuilt every second and redrew the same frozen number, so the
/// clock only moved when HealthKit delivered a batch. `elapsed(at:)` falls back
/// to the pushed snapshot when there is no basis, which is what keeps the
/// seeded capture session byte-identical between runs.
struct WatchSessionClock: View {
    let metrics: WatchWorkoutMetrics
    var size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(metrics.elapsed(at: context.date).walkClockText)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}
