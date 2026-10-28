import FouleeKit
import SwiftUI

/// The pages of a live session, left to right (issues #274, #276, ADR 0008).
///
/// Selection binds to **these cases, never to an index**: « Jambes » only
/// appears once an outing has changed sport, so the position of everything
/// after it moves at runtime.
///
/// The Exercice app's order: « Contrôles » to the left of « Séance », which is
/// the page a session opens on, and « Musique » to its right. Stopping and
/// pausing are one swipe away in one direction, the music one swipe away in
/// the other, and a wearer who knows the Exercice app finds both where they
/// expect them. « Plan » follows (issue #312): it is the page read while
/// moving, the others are glanced at. « Journée » closes the row, with the
/// water in it (issue #281): the two answered the same question — how is the
/// day going — on two pages.
enum WatchSessionPage: Hashable {
    case controls
    case session
    case music
    case route
    case legs
    case day
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
/// paged `TabView` keeps noticeably more room above its content than a plain
/// scroll view, so the first capture of the paged screen still cut « kcal » and
/// « bpm » off the bottom of a **46 mm** — the roomiest watch in the set. What
/// actually made it fit was measuring the board and then cutting: two-line
/// metric tiles instead of three, a 34 pt clock instead of 38, tighter spacing,
/// and no `Divider()`. Verified on a 40 mm SE probe, at default text size, with
/// room to spare.
///
/// The pages keep their scroll views for the largest Dynamic Type sizes, where
/// nothing fits on any wrist.
///
/// **The axis is horizontal, and issue #274 got that wrong.** It shipped
/// `.verticalPage`, reasoning that Apple only spends its horizontal axis on Now
/// Playing, which Foulée does not have. That is a *content* argument, and the
/// mechanism points the other way: these pages scroll vertically, so a vertical
/// pager competes with them for the same gesture. On a 46 mm the pager happened
/// to win; **on a 40 mm the inner scroll view swallowed the swipe and the page
/// never changed** — which means a wearer could not have reached « Arrêter » by
/// swiping at all. That is issue #241's defect returning by another route, and
/// it was caught by the 40 mm capture probe rather than by review.
///
/// So Apple does not put its pages on the horizontal axis out of taste. It puts
/// them there because its pages scroll. `.page` costs the index dots ~10 pt at
/// the bottom, which both wrists were measured to afford.
///
/// **No `navigationTitle`.** There is no `NavigationStack` here on purpose — a
/// swipe-back gesture and a paging gesture on the same view is a conflict this
/// screen does not need — and `navigationTitle` renders nothing without one.
/// Neither page carries a drawn header either: a 34 pt clock and a button
/// reading « Arrêter » say what they are, and a header line would cost 14–18 pt
/// of the very budget this change exists to recover. VoiceOver gets the naming
/// instead, through `accessibilityLabel` on each page, which costs no pixels.
/// The later pages carry their own labels in their content — « j de série »,
/// « / 10 000 pas », the sport at the head of each leg — so none of them has
/// needed a header either. The rule is not « never a header »: it is that a
/// header has to buy back the 14–18 pt it costs, and so far the content has.
struct WatchSessionPager: View {
    let metrics: WatchWorkoutMetrics
    let today: WatchTodayStore
    let route: WatchRouteStore
    var errorMessage: String?
    /// The outing is being saved after « Arrêter » (issue #380).
    var isSaving = false
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void

    @State private var page: WatchSessionPage = .session

    var body: some View {
        TabView(selection: $page) {
            WatchSessionControlsPage(metrics: metrics, isSaving: isSaving, onTogglePause: onTogglePause, onStop: onStop)
                .tag(WatchSessionPage.controls)
            WatchSessionMetricsPage(metrics: metrics, errorMessage: errorMessage)
                .tag(WatchSessionPage.session)
            WatchSessionMusicPage()
                .tag(WatchSessionPage.music)
            WatchSessionRoutePage(route: route, metrics: metrics)
                .tag(WatchSessionPage.route)
            if showsLegs {
                WatchSessionLegsPage(metrics: metrics)
                    .tag(WatchSessionPage.legs)
            }
            WatchSessionDayPage(today: today)
                .tag(WatchSessionPage.day)
        }
        .tabViewStyle(.page)
        // Each kilometre, over whatever page is up (issue #382).
        .kilometreAlert(metrics.splits)
        // Over every page, not only « Contrôles »: the summary takes seconds to
        // come, and whatever page is on screen has to say the tap was heard.
        .overlay {
            if isSaving {
                WatchSavingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isSaving)
        .sensoryFeedback(.stop, trigger: isSaving) { _, saving in saving }
        .sensoryFeedback(trigger: metrics.isPaused) { _, paused in paused ? .stop : .start }
        // Only while « Journée » is the page on screen (issue #280). Attached
        // to the pager rather than to the page, and keyed on the selection, so
        // arriving starts the loop and leaving cancels it: nothing guarantees a
        // paged `TabView` does not build its neighbours ahead of time, and a
        // page built off screen must not be querying HealthKit every minute.
        .task(id: page) {
            guard page == .day else { return }
            while !Task.isCancelled {
                await today.refreshForSession()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// « Jambes » exists only once the outing has been split (issue #276).
    ///
    /// There is always at least one leg — the one in flight — so a single-leg
    /// outing would give the page a lone row repeating the clock two pages up.
    /// It appears at the moment it has something to say, which is the same rule
    /// `WatchWorkoutMetrics.perSport` already follows on the recap.
    ///
    /// Legs are only ever appended during a session, so this never flips back
    /// to `false` under a reader standing on the page.
    private var showsLegs: Bool { metrics.legs.count > 1 }
}

/// The elapsed clock.
///
/// **Drawn by the system, the way the Live Activity draws it** (issue #458).
/// It used to be a `TimelineView` redrawing one `Text` every second. On an
/// Apple Watch SE that timeline never refreshed: the clock sat at 00:00 while
/// the heart rate kept moving and the iPhone's Live Activity — fed the very
/// same `timerBasis` — counted correctly. `Text(timerInterval:)` hands the
/// ticking to the system, so there is no timeline to keep alive at all.
///
/// Still a function of the basis and never of `metrics.elapsed` while it runs:
/// that was the whole of issue #266.
///
/// `size` is the default text size's; the clock grows with the wearer's text
/// size and shrinks back to one line rather than wrap (issue #600). VoiceOver
/// hears it in words: « 12:34 » alone is read as a time of day.
struct WatchSessionClock: View {
    let metrics: WatchWorkoutMetrics
    var size: CGFloat

    var body: some View {
        reading
            .scaledNumericFont(size: size, weight: .semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel("Durée")
            .accessibilityValue(spokenDurationText(seconds: metrics.elapsed(at: .now)))
    }

    @ViewBuilder private var reading: some View {
        switch metrics.clockReading {
        case .running(let start):
            Text(timerInterval: start...start.addingTimeInterval(WatchWorkoutMetrics.clockSpan), countsDown: false)
        case .stopped(let elapsed):
            Text(elapsed.walkClockText)
        }
    }
}

extension View {
    /// A page of the session pagers, named for VoiceOver rather than drawn on
    /// screen (see `WatchSessionPager`). A container, so the name is the
    /// page's own and not handed to every element on it (issue #600).
    func sessionPage(_ name: LocalizedStringKey) -> some View {
        accessibilityElement(children: .contain)
            .accessibilityLabel(name)
    }
}
