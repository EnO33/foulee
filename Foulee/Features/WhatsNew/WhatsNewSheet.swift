import FouleeKit
import SwiftUI

extension View {
    /// The « Nouveautés » of a notable version (issue #621), over the home at
    /// its first appearance after the update. `isAllowed` is false until the
    /// home has loaded and while a session covers it: a shortcut that opened
    /// one at launch leaves the screen for later. Never over another sheet.
    func whatsNewPresentation(isAllowed: Bool, colorScheme: ColorScheme) -> some View {
        modifier(WhatsNewPresentation(isAllowed: isAllowed, colorScheme: colorScheme))
    }
}

private struct WhatsNewPresentation: ViewModifier {
    let isAllowed: Bool
    let colorScheme: ColorScheme
    private let store = WhatsNewStore.shared
    @State private var release: WhatsNewRelease?

    func body(content: Content) -> some View {
        content
            .onChange(of: isAllowed, initial: true) { _, allowed in
                guard allowed, release == nil, UIApplication.shared.isHomeFrontmost else { return }
                release = store.pending()
            }
            .sheet(item: $release) { release in
                WhatsNewSheet(release: release) { self.release = nil }
                    .presentationBackground { SheetBackground() }
                    .preferredColorScheme(colorScheme)
                    .onAppear { store.markSeen() }
            }
    }
}

/// What changed in this version: one row per change, and a button to go on.
struct WhatsNewSheet: View {
    let release: WhatsNewRelease
    var onClose: () -> Void

    /// The language the screens are shown in, so the rows read like them.
    private let language = Locale.app.language.languageCode?.identifier ?? "fr"

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SheetHeader(eyebrow: "Version \(release.version)", title: "Nouveautés")
                    ForEach(release.items, id: \.icon) { item in
                        row(item)
                    }
                }
                .padding(.top, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
            PrimaryButton(title: "C'est noté", action: onClose)
                .padding(.bottom, 8)
        }
        .screenColumn(gutter: 24)
    }

    private func row(_ item: WhatsNewItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: item.icon)
                .scaledSystemFont(size: 26, weight: .semibold)
                .foregroundStyle(FouleeColor.accentGradient)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.title(in: language))
                    .font(FouleeFont.headline)
                Text(verbatim: item.text(in: language))
                    .font(FouleeFont.callout)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WhatsNewSheet(release: WhatsNewStore.bundled().first ?? WhatsNewRelease(version: "1.59", items: [])) {}
        .background(SheetBackground())
}
