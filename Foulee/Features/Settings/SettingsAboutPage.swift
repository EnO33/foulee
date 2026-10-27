import SwiftUI

/// À propos (issue #396): which build this is — what a bug report needs —
/// and where to read the policy, get help, or see the code.
struct SettingsAboutPage: View {
    private let version = AppVersion.current

    var body: some View {
        GlassSection(footer: "Appui long sur la version pour la copier.") {
            row(label: "Version", value: version)
                .contextMenu {
                    Button("Copier la version", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = version
                    }
                }
            Divider()
            row(label: "Auteur", value: "EnO33")
            Divider()
            row(label: "Licence", value: "MIT")
        }
        GlassSection {
            link("Politique de confidentialité", icon: "hand.raised.fill", url: AppLinks.privacyPolicy)
            Divider()
            link("Assistance", icon: "lifepreserver.fill", url: AppLinks.support)
            Divider()
            link("FAQ Garmin", icon: "questionmark.circle.fill", url: AppLinks.garminFAQ)
            Divider()
            link("Signaler un problème", icon: "exclamationmark.bubble.fill", url: AppLinks.reportIssue)
            Divider()
            link("Code source", icon: "chevron.left.forwardslash.chevron.right", url: AppLinks.sourceCode)
        }
    }

    private func row(label: LocalizedStringResource, value: String) -> some View {
        HStack {
            Text(label).font(FouleeFont.body)
            Spacer()
            Text(value).font(FouleeFont.body.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Opens in the browser — `Link` hands the URL to the system, which
    /// shows it outside the app.
    private func link(_ title: LocalizedStringResource, icon: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(FouleeColor.accentMid)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(FouleeFont.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityHint("S'ouvre dans le navigateur")
    }
}
