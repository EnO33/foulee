import SwiftUI

/// The round « × » every sheet closes with (issue #392). One definition so
/// the nine sheets stop drifting apart — the shadow keeps it readable over a
/// map as well as over the sheet gradient.
struct SheetCloseButton: View {
    var accessibilityLabel = "Fermer"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .buttonStyle(.pressable)
        .padding(20)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Small caps eyebrow over a large title — the opening line of a sheet
/// (« RÉCAP / Ton bilan », « HYDRATATION / Aujourd'hui »…).
struct SheetHeader: View {
    var eyebrow: String
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text(title)
                .font(FouleeFont.largeTitle)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A titled glass card: the one way a sheet groups related content. The title
/// sits inside the card, an optional footnote under its content.
struct GlassSection<Content: View>: View {
    var title: String?
    var footer: String?
    let content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(FouleeFont.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            content
            if let footer {
                Text(footer)
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .fouleeGlass(cornerRadius: 22)
    }
}
