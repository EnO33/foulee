import SwiftUI

/// Three progress dots; the active one stretches into a pill.
struct OnboardingStepIndicator: View {
    var step: Int
    var total: Int = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? AnyShapeStyle(FouleeColor.accentMid) : AnyShapeStyle(Color.gray.opacity(0.3)))
                    .frame(width: index == step ? 22 : 8, height: 8)
                    .animation(.easeOut(duration: 0.2), value: step)
            }
        }
    }
}
