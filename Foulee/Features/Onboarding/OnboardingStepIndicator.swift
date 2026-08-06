import SwiftUI

/// One progress dot per `OnboardingStep`; the active one stretches into a
/// pill. The count comes from the enum rather than a `total` parameter, so a
/// new step can't leave the dots behind (issue #221).
struct OnboardingStepIndicator: View {
    var step: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                Capsule()
                    .fill(
                        candidate.rawValue <= step.rawValue
                            ? AnyShapeStyle(FouleeColor.accentMid)
                            : AnyShapeStyle(Color.gray.opacity(0.3))
                    )
                    .frame(width: candidate == step ? 22 : 8, height: 8)
                    .animation(.easeOut(duration: 0.2), value: step)
            }
        }
    }
}
