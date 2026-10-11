import SwiftUI

/// Round day chip for picking active days — shared by the onboarding goal
/// step and the Réglages planning page, so both read the same.
struct DayChip: View {
    var day: Weekday
    var active: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            // The circle stays 40 pt (7 chips must fit one row), so the label
            // scales with Dynamic Type until it hits the circle, then shrinks.
            Text(day.shortLabel)
                .font(.system(.subheadline, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(active ? AnyShapeStyle(FouleeColor.accentGradient) : AnyShapeStyle(Color.clear))
                )
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(active ? 0 : 0.25), lineWidth: 1)
                )
                .shadow(color: FouleeColor.accentMid.opacity(active ? 0.35 : 0), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.pressable)
    }
}
