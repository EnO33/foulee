import SwiftUI

/// Small pill with optional leading SF Symbol — used for status badges
/// ("EN COURS", "Marche dans 18 min", "3 / 5 marches", …).
struct Chip: View {
    var label: String
    var systemIcon: String?
    var tint: Color = .primary
    var fill: Color = Color.gray.opacity(0.16)

    var body: some View {
        HStack(spacing: 6) {
            if let systemIcon {
                Image(systemName: systemIcon)
                    .font(FouleeFont.footnote.weight(.semibold))
            }
            Text(label)
                .font(FouleeFont.footnote.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(fill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
