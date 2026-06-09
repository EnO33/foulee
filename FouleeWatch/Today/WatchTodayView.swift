import Combine
import SwiftUI

/// Watch home: today's streak + key numbers, and the "Démarrer" CTA. Replaces
/// the old bare idle screen so the watch is useful at a glance, not only mid-walk.
struct WatchTodayView: View {
    let store: WatchTodayStore
    var errorMessage: String?
    var onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                streakHero
                statsGrid
                startButton
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 2)
        }
        .task { await store.load() }
        .onReceive(NotificationCenter.default.publisher(for: .watchSyncReceived)) { _ in
            Task { await store.load() }
        }
    }

    private var streakHero: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.orange)
                Text("\(store.streak)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("j")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text("série")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            stat(icon: "shoeprints.fill", tint: .purple, value: store.steps.formatted(), label: "pas")
            stat(icon: "timer", tint: .green, value: "\(store.minutes)", label: "min")
            stat(icon: "ruler.fill", tint: .blue, value: kmText, label: "km")
            stat(icon: "flame.fill", tint: .orange, value: "\(store.calories)", label: "kcal")
        }
    }

    private func stat(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var startButton: some View {
        Button(action: onStart) {
            Label("Démarrer", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("AccentColor"))
        .padding(.top, 2)
    }

    private var kmText: String {
        String(format: "%.1f", store.distanceKm).replacingOccurrences(of: ".", with: ",")
    }
}
