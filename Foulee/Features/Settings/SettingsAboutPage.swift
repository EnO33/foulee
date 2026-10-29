import FouleeKit
import SwiftUI

/// À propos (issue #396): which build this is — what a bug report needs —
/// and where to read the policy, get help, or see the code. A report can
/// carry the device's diagnostics, only if the user chooses (issue #610).
struct SettingsAboutPage: View {
    private let version = AppVersion.current
    @State private var report: ProblemReport?
    @State private var attachesSummary = true

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
            link("Code source", icon: "chevron.left.forwardslash.chevron.right", url: AppLinks.sourceCode)
        }
        GlassSection(
            "Signaler un problème",
            footer: "Rien ne part sans toi. Le résumé ne contient ni donnée de santé ni position."
        ) {
            SettingsToggle(
                "Joindre le résumé",
                detail: "Version, appareil et derniers incidents",
                isOn: $attachesSummary
            )
            if let report {
                DisclosureGroup("Voir le résumé") {
                    Text(verbatim: report.summary)
                        .font(FouleeFont.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .font(FouleeFont.body)
            }
            Divider()
            link("Ouvrir un signalement", icon: "exclamationmark.bubble.fill", url: issueURL)
            if let report {
                Divider()
                ShareLink(item: report.fullReport, preview: SharePreview("Rapport de diagnostic Foulée")) {
                    label("Partager le rapport complet", icon: "square.and.arrow.up", trailing: "chevron.right")
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Avec les traces techniques, pour un envoi privé")
            }
        }
        .task { report = await DiagnosticsCollector.shared.report() }
    }

    private var issueURL: URL {
        guard attachesSummary, let report else { return AppLinks.reportIssue }
        return AppLinks.reportIssue(body: report.issueBody)
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
            label(title, icon: icon, trailing: "arrow.up.right")
        }
        .buttonStyle(.pressable)
        .accessibilityHint("S'ouvre dans le navigateur")
    }

    private func label(_ title: LocalizedStringResource, icon: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(FouleeColor.accentMid)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(FouleeFont.body)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: trailing)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
