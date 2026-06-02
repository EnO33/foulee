import SwiftUI

/// Quick midday-weather detail, opened by tapping the weather card. Local-only
/// data (the single midday snapshot the Today screen already has) — no chart.
struct WeatherDetailSheet: View {
    let weather: WeatherSnapshot
    var onClose: () -> Void

    private var isAvailable: Bool { weather.condition != "—" }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SheetBackground()
            content
            closeButton.padding(20)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAvailable {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: FouleeIcon.sun)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(FouleeColor.streakGradient)
                    .symbolRenderingMode(.hierarchical)
                Text("\(weather.temperatureCelsius)°C")
                    .font(FouleeFont.numeric(size: 64))
                Text(weather.condition)
                    .font(FouleeFont.title2)
                adviceRow
                Spacer()
                Text("Météo du midi à ton emplacement")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
        } else {
            unavailable
        }
    }

    private var adviceRow: some View {
        HStack(spacing: 8) {
            Image(systemName: FouleeIcon.walk)
                .foregroundStyle(FouleeColor.accentMid)
            Text("Conseil : \(weather.advice)")
                .font(FouleeFont.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fouleeGlass(cornerRadius: 16)
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Météo indisponible")
                .font(FouleeFont.headline)
            Text("Autorise la localisation pour voir la météo de midi à ton endroit.")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Fermer")
    }
}

#Preview("Ensoleillé") {
    WeatherDetailSheet(
        weather: WeatherSnapshot(temperatureCelsius: 21, condition: "Ensoleillé", advice: "idéal"),
        onClose: {}
    )
}

#Preview("Indisponible") {
    WeatherDetailSheet(
        weather: WeatherSnapshot(temperatureCelsius: 0, condition: "—", advice: ""),
        onClose: {}
    )
}
