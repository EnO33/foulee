import SwiftUI

/// Gates the rest of the app on `UserPreferences.hasCompletedOnboarding`.
/// First-launch users see the 3-step onboarding; everyone else lands on
/// the Today screen.
struct RootView: View {
    @State private var preferences = UserPreferences()

    var body: some View {
        Group {
            if preferences.hasCompletedOnboarding {
                TodayScreen()
            } else {
                OnboardingFlow(preferences: preferences) {
                    preferences.hasCompletedOnboarding = true
                }
            }
        }
        .environment(preferences)
    }
}

#Preview {
    RootView()
}
