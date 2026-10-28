import SwiftUI

/// Apple Weather attribution required by App Store Review Guideline 5.2.5 for
/// any app that surfaces WeatherKit data: the Apple Weather trademark plus an
/// active link to Apple's legal data-sources page. Shown wherever the app
/// displays weather (the home weather card row and the weather detail sheet).
struct WeatherAttributionView: View {
    /// Apple's required legal attribution / data-sources page.
    static let legalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Link(destination: Self.legalURL) {
            // On two lines at the accessibility sizes (#597): the attribution
            // is required, so it is never cut to « Weat… ». One tree whose
            // layout changes, not a `ViewThatFits` between two, which the
            // accessibility audit read as « Dynamic Type partially
            // unsupported » (issue #658).
            AdaptiveStack(stacked: VStackLayout(spacing: 2), regular: HStackLayout(spacing: 5)) {
                trademark
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(verbatim: "·")
                }
                sources
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Apple Weather, sources des données")
    }

    /// U+F8FF renders as the Apple logo in the system font, giving the
    /// required " Weather" trademark.
    private var trademark: some View {
        Text(verbatim: "\u{F8FF} Weather")
            .font(FouleeFont.caption.weight(.semibold))
    }

    private var sources: some View {
        HStack(spacing: 5) {
            Text("Sources des données")
                .font(FouleeFont.caption)
            Image(systemName: "arrow.up.right")
                .scaledSystemFont(size: 9, weight: .bold)
        }
    }
}

#Preview {
    WeatherAttributionView()
}
