import SwiftUI

/// The screen shown for one onboarding step.
///
/// This switch used to live inside `OnboardingFlow.body`, where nothing could
/// reach it: the step it reads is `@State private`, so a test can't put the
/// flow on a given step, and a `@ViewBuilder` body can't be asserted on from
/// the outside. The mapping could therefore be rewired — `.activity` rendering
/// the goal screen, the activity screen never rendered at all — with the build
/// green and the whole suite silent. That is the same failure the `default:`
/// catch-all shipped before #221, only moved one level up.
///
/// Pulled out into its own view, the mapping is a value a test constructs one
/// step at a time (`OnboardingFlowTests.eachStepRendersItsOwnScreen`).
struct OnboardingStepScreen: View {
    var step: OnboardingStep
    var preferences: UserPreferences
    /// Move to the next step. The last screen calls `finish` instead.
    var advance: () -> Void
    /// Hand control back to the container, which closes the onboarding gate.
    var finish: () -> Void

    /// Exhaustive on purpose — no `default:`. The catch-all this replaces
    /// rendered the permissions screen for any index it didn't recognise, so a
    /// step added without a screen was a silent runtime surprise; now it's a
    /// build failure.
    var body: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeView(onContinue: advance)
        case .activity:
            OnboardingActivityView(preferences: preferences, onContinue: advance)
        case .goal:
            OnboardingGoalView(preferences: preferences, onContinue: advance)
        case .permissions:
            OnboardingPermissionsView(preferences: preferences, onFinish: finish)
        }
    }
}
