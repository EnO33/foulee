import SwiftUI

/// Freshness hint shown on the Today screen when the user's data comes from a
/// Garmin watch only and the day looks behind (see `GarminFreshness`).
///
/// Deliberately the *only* hint in that state: complications, "ouvre l'app
/// Watch" and other Apple-Watch-flavoured advice would be dead ends for
/// someone who doesn't own one. Informational on purpose — Foulée doesn't try
/// to launch Garmin Connect: a third-party URL scheme that silently fails
/// would be worse than a sentence the user can act on.
struct GarminSyncHintCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(FouleeColor.accentMid)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ouvre Garmin Connect pour synchroniser")
                    .font(FouleeFont.footnote.weight(.semibold))
                Text("Ta montre envoie ses données à Santé par rafales, quand tu ouvres l'app Garmin Connect.")
                    .font(FouleeFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .fouleeGlass(cornerRadius: 16)
    }
}

#Preview("Light") { GarminSyncHintCard().padding().preferredColorScheme(.light) }
#Preview("Dark") { GarminSyncHintCard().padding().preferredColorScheme(.dark) }
