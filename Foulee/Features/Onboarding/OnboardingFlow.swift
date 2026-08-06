import SwiftUI

/// 4-step onboarding container. Linear (no back nav by design — every step
/// either commits a default-acceptable value or doesn't change anything).
///
/// The activity question sits at `.activity`, right after the welcome: with no
/// way back, a decision the later screens are written around has to be taken
/// before them, not after (issue #221).
struct OnboardingFlow: View {
    @Bindable var preferences: UserPreferences
    var onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome

    var body: some View {
        ZStack {
            Wallpaper()
            // The step → screen mapping lives in `OnboardingStepScreen`: from
            // in here it would sit behind `@State private var step`, out of
            // reach of any test.
            OnboardingStepScreen(
                step: step,
                preferences: preferences,
                advance: advance,
                // Just forwards: `RootView` owns the completion flag, because
                // it owns the gate that reads it. Writing it here as well —
                // as this flow did until #221's review — made two writers for
                // one boolean, and the copy that mattered was never the one
                // any test could reach.
                finish: onFinish
            )
            .id(step)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .animation(.easeOut(duration: 0.25), value: step)
    }

    private func advance() {
        step = step.next
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
