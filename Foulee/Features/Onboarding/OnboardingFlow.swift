import SwiftUI

/// 3-step onboarding container. Linear (no back nav by design — every step
/// either commits a default-acceptable value or doesn't change anything).
struct OnboardingFlow: View {
    @Bindable var preferences: UserPreferences
    var onFinish: () -> Void

    @State private var step: Int = 0

    var body: some View {
        ZStack {
            Wallpaper()
            content
                .id(step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .animation(.easeOut(duration: 0.25), value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            OnboardingWelcomeView { advance() }
        case 1:
            OnboardingGoalView(preferences: preferences) { advance() }
        default:
            OnboardingPermissionsView(preferences: preferences) {
                preferences.hasCompletedOnboarding = true
                onFinish()
            }
        }
    }

    private func advance() {
        step = min(step + 1, 2)
    }
}

private struct OnboardingPreview: View {
    @State private var preferences = UserPreferences(
        defaults: UserDefaults(suiteName: "preview-onboarding") ?? .standard
    )
    var body: some View {
        OnboardingFlow(preferences: preferences, onFinish: {})
    }
}

#Preview("Light") { OnboardingPreview().preferredColorScheme(.light) }
#Preview("Dark") { OnboardingPreview().preferredColorScheme(.dark) }
