import FouleeKit
import SwiftUI

/// Quick weather detail, opened by tapping the weather on the hero. Local-only
/// data (the single forecast the Today screen already has) — no chart.
struct WeatherDetailSheet: View {
    let weather: WeatherSnapshot
    /// The hour the forecast is for: the start of the outing window.
    var windowStart: DateComponents
    /// Why there is no forecast, read only when `weather` is unavailable.
    var location: Access = .unknown
    var onClose: () -> Void

    private var isAvailable: Bool { weather.isAvailable }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SheetBackground()
            content
            SheetCloseButton(action: onClose)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAvailable {
            // Scrolls only when the text is too large to fit (#597): squeezed
            // into the screen, the advice was cut to « Conseil : i… ». At
            // least the screen's height, so the spacers still centre it.
            //
            // One tree at every size, not a `ViewThatFits` between two: the
            // accessibility audit read every text of the swap as « Dynamic
            // Type partially unsupported » and the forecast line as clipped
            // (issue #658).
            GeometryReader { proxy in
                ScrollView {
                    forecast.frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        } else {
            unavailable
        }
    }

    private var forecast: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: FouleeIcon.sun)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(FouleeColor.streakGradient)
                .symbolRenderingMode(.hierarchical)
            Text("\(weather.temperatureCelsius)°C")
                .scaledNumericFont(size: 64)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(weather.condition)
                .font(FouleeFont.title2)
            adviceRow
            Spacer()
            // "à 18:30", not "de 18:30": the latter reads as a span as
            // easily as an hour.
            Text("Prévision à \(windowStart.clockText) à ton emplacement")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
            WeatherAttributionView()
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    private var adviceRow: some View {
        HStack(spacing: 8) {
            Image(systemName: FouleeIcon.mixedCardio)
                .foregroundStyle(FouleeColor.accentMid)
                .accessibilityHidden(true)
            Text("Conseil : \(weather.advice)")
                .font(FouleeFont.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fouleeGlass(cornerRadius: 16)
    }

    private var unavailable: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            DegradedBanner(state: .weather(location: location))
        }
        .padding(.horizontal, 28)
    }
}

#Preview("Ensoleillé") {
    WeatherDetailSheet(
        weather: WeatherSnapshot(temperatureCelsius: 21, condition: "Ensoleillé", advice: "idéal"),
        windowStart: DateComponents(hour: 12, minute: 30),
        onClose: {}
    )
}

#Preview("Indisponible") {
    WeatherDetailSheet(
        weather: WeatherSnapshot(temperatureCelsius: 0, condition: "—", advice: ""),
        windowStart: DateComponents(hour: 12, minute: 30),
        location: .denied,
        onClose: {}
    )
}
