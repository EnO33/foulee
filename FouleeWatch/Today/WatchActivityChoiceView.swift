import SwiftUI

/// « Les deux » : which activity is this session? (issue #224)
///
/// A full screen, not an extra control on the home. The home is already dense
/// — streak hero, 2×2 grid, optional hydration card, then the CTA — and the
/// two shapes that fit "in place" both cost something worse than a tap: a
/// second start button permanently changes that layout for a screen read
/// outdoors at a glance, and a long-press on the existing one hides the choice
/// where nobody finds it. Here each answer gets the full width of the watch,
/// stacked, with nothing else on screen to mis-hit, and the crown scrolls it
/// at the largest Dynamic Type sizes. Users in « marche » or « course » never
/// reach it.
///
/// « Annuler » is a real button rather than a swipe: it is the only way back,
/// so it must be visible — and it is pinned outside the `ScrollView`, exactly
/// as the phone's `ActivityChoiceScreen` pins its own. Inside it, on a 40 mm
/// watch, it sat below the bottom of the screen at the default text size and
/// was gone entirely at the larger ones, leaving a screen whose only visible
/// controls each start a permanent workout and no way out at all.
///
/// What this screen removes is the *silent* mislabelling, not the mis-tap:
/// answering starts the session at once and `WatchWorkoutStore.stop()` saves
/// unconditionally, so « Course » tapped by mistake is still a permanent run.
/// Discarding a session already under way would be an action on the active
/// screen — its own issue.
struct WatchActivityChoiceView: View {
    var onChoose: (SessionActivity) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    Text("Marche ou course ?")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .padding(.bottom, 2)
                    ForEach(SessionActivity.allCases, id: \.self) { activity in
                        WatchActivityChoiceButton(activity: activity, select: { onChoose(activity) })
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            WatchActivityCancelButton(cancel: onCancel)
                .padding(.horizontal, 2)
                .padding(.top, 4)
        }
    }
}

/// One full-width answer. Internal rather than private for the same reason as
/// the phone's `ActivityChoiceButton`: `ForEach` stores a closure instead of
/// its rows, and calling it is the only way a test can reach the tap action.
struct WatchActivityChoiceButton: View {
    var activity: SessionActivity
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            Label(activity.label, systemImage: activity.icon)
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("AccentColor"))
    }
}

/// The way back out, and on the watch it is the *only* one — there is no
/// navigation bar behind this screen to swipe back to. Named for the same
/// reason the answers are: wired to nothing it strands the user on a screen
/// that replaced their home.
struct WatchActivityCancelButton: View {
    var cancel: () -> Void

    var body: some View {
        Button(action: cancel) {
            Text("Annuler")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    WatchActivityChoiceView(onChoose: { _ in }, onCancel: {})
}
