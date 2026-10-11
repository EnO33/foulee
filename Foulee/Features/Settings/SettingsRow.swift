import SwiftUI

/// One line of the Réglages home: a tinted glyph, the setting's name, its
/// current value, and a chevron — the iOS Settings grammar in Foulée glass.
/// A label only: the caller wraps it in a `NavigationLink` or a `Button`.
struct SettingsRow: View {
    var icon: String
    var tint: Color
    var title: String
    var summary: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .scaledSystemFont(size: 16, weight: .semibold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FouleeFont.headline)
                    .foregroundStyle(.primary)
                Text(summary)
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The whole line is the hit area, not just its glyphs.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
