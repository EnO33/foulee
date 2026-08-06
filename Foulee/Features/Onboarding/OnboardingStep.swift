import Foundation

/// The onboarding screens, in order.
///
/// The flow is linear with no back navigation, so "which screen" is only a
/// rank — but until #221 that rank lived as four independent literals: a
/// `default:` catch-all in the flow's switch, a `min(step + 1, 2)` clamp, the
/// indicator's `total = 3`, and one `step:` number per screen. Nothing tied
/// them together, and the catch-all was the dangerous one: it rendered the
/// permissions screen for *every* index above 1, so adding a fourth screen
/// would have produced a ghost screen at runtime instead of a compile error.
///
/// One enum removes all four. The switch over it is exhaustive (a new case
/// fails the build until it has a screen), the clamp becomes "there is no
/// next case", and the indicator counts `allCases` instead of hardcoding a
/// total. Adding or reordering a step is now a single edit here.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case activity
    case goal
    case permissions

    /// The next screen, or self on the last one — the flow only ever moves
    /// forward, and the final screen finishes instead of advancing.
    var next: OnboardingStep {
        OnboardingStep(rawValue: rawValue + 1) ?? self
    }
}
