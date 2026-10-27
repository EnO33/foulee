import SwiftUI

/// A headline over a control, with an optional footnote — one row inside a
/// settings card that holds several (the Hydratation page).
struct SettingsField<Content: View>: View {
    var title: LocalizedStringResource
    var footer: LocalizedStringResource?
    let content: Content

    init(_ title: LocalizedStringResource, footer: LocalizedStringResource? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(FouleeFont.headline)
            content
            if let footer {
                Text(footer)
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
