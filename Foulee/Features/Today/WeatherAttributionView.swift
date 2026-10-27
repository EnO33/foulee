import SwiftUI

/// Apple Weather attribution required by App Store Review Guideline 5.2.5 for
/// any app that surfaces WeatherKit data: the Apple Weather trademark plus an
/// active link to Apple's legal data-sources page. Shown wherever the app
/// displays weather (the home weather card row and the weather detail sheet).
struct WeatherAttributionView: View {
    /// Apple's required legal attribution / data-sources page.
    static let legalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        Link(destination: Self.legalURL) {
            // On two lines when one is too narrow (#597): the attribution is
            // required, so it is never cut to « Weat… ».
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    trademark
                    Text(verbatim: "·")
                    sources
                }
                VStack(spacing: 2) {
                    trademark
                    sources
                }
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
