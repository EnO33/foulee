import SwiftUI

/// Drinking, without leaving the session (issue #281).
///
/// The same card the home draws, and the same store behind it — see
/// `WatchHydrationCard`. The page exists because the moment someone most wants
/// to log a glass is the moment they are least able to leave the session screen
/// to do it.
///
/// Second departure from the Workout HIG, on the same argument as « Journée »
/// and stated for the same reason: an outing is what makes the wearer thirsty,
/// so the water belongs where the outing is.
///
/// Verified rather than assumed: `dietaryWater` is **not** in
/// `collectedQuantityTypes`, so writing a glass mid-session touches nothing the
/// `HKLiveWorkoutBuilder` is collecting.
struct WatchSessionHydrationPage: View {
    let today: WatchTodayStore

    var body: some View {
        ScrollView {
            WatchHydrationCard(store: today)
                .padding(.horizontal, 6)
                .padding(.top, 4)
        }
        .accessibilityLabel("Hydratation")
    }
}
