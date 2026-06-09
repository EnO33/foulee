import SwiftUI

/// Gates the hydration card on the home behind the user's preference and wires
/// the "J'ai bu" tap to the store. Split out of `TodayScreen` to keep that
/// view's body small.
struct HydrationHomeCard: View {
    let preferences: UserPreferences
    let store: HydrationStore

    var body: some View {
        if preferences.hydrationEnabled {
            HydrationCard(
                intakeML: store.intakeML,
                goalML: preferences.hydrationGoalML,
                glassML: preferences.hydrationGlassML
            ) {
                Task { await store.logGlass(ml: preferences.hydrationGlassML) }
            }
            .padding(.horizontal, 20)
        }
    }
}
