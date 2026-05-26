import SwiftUI

/// Two side-by-side glass cards: current streak + midday weather.
struct TodayStreakWeatherRow: View {
    var snapshot: TodaySnapshot

    var body: some View {
        HStack(spacing: 12) {
            streakCard
            weatherCard
        }
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: FouleeIcon.flame)
                    .font(.system(size: 20))
                    .foregroundStyle(FouleeColor.warning)
                Text("SÉRIE")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.streak)")
                    .font(FouleeFont.numeric(size: 30))
                Text("jours")
                    .font(FouleeFont.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Record : \(snapshot.bestStreak) jours")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .fouleeGlass(cornerRadius: 22)
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: FouleeIcon.sun)
                    .font(.system(size: 20))
                    .foregroundStyle(FouleeColor.warning)
                Text("MIDI")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.weather.temperatureCelsius)°")
                    .font(FouleeFont.numeric(size: 30))
                Text("C")
                    .font(FouleeFont.callout)
                    .foregroundStyle(.secondary)
            }
            Text("\(snapshot.weather.condition) · \(snapshot.weather.advice)")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .fouleeGlass(cornerRadius: 22)
    }
}
