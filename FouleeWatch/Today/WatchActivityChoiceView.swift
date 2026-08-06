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
/// so it must be visible.
struct WatchActivityChoiceView: View {
    var onChoose: (SessionActivity) -> Void
    var onCancel: () -> Void

    var body: some View {
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
                WatchActivityCancelButton(cancel: onCancel)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
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
