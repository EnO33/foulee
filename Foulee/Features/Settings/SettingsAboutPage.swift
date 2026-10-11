import SwiftUI

/// À propos: which build this is, and whose.
struct SettingsAboutPage: View {
    private let appVersion: String = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    var body: some View {
        GlassSection {
            row(label: "Version", value: appVersion)
            Divider()
            row(label: "Auteur", value: "EnO33")
            Divider()
            row(label: "Licence", value: "MIT")
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).font(FouleeFont.body)
            Spacer()
            Text(value).font(FouleeFont.body).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
