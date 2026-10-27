import SwiftUI

/// Icon + label + big value (+ optional subtitle) — the unit cell of the
/// "Aujourd'hui" stats grid (pas / minutes / distance / calories).
struct StatBlock: View {
    var systemIcon: String
    var label: LocalizedStringResource
    var value: String
    var sub: String?
    /// The value as VoiceOver says it, when the written one reads wrong —
    /// « 8 432 sur 10 000 » rather than « 8 432 barre oblique 10 000 ».
    var spokenValue: String?
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemIcon)
                    .font(FouleeFont.footnote.weight(.semibold))
                Text(label)
                    .font(FouleeFont.footnote.weight(.semibold))
            }
            .foregroundStyle(tint)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .scaledNumericFont(size: 26)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let sub {
                    Text(sub)
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(spokenValue ?? sub.map { "\(value) \($0)" } ?? value)
    }
}
