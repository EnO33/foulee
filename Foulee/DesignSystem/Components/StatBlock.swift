import SwiftUI

/// Icon + label + big value (+ optional subtitle) — the unit cell of the
/// "Aujourd'hui" stats grid (pas / minutes / distance / calories).
struct StatBlock: View {
    var systemIcon: String
    var label: String
    var value: String
    var sub: String?
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
                    .font(FouleeFont.numeric(size: 26))
                if let sub {
                    Text(sub)
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
