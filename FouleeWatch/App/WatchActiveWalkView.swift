import SwiftUI

/// Live session screen — uses a `TimelineView` so the elapsed clock keeps
/// ticking even when the store hasn't pushed an update yet (HealthKit
/// metric updates arrive every few seconds, the clock needs to be smoother).
struct WatchActiveWalkView: View {
    let metrics: WatchWorkoutMetrics
    var onStop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 8) {
                Text(format(elapsed: metrics.elapsed))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 10) {
                    metric(value: "\(metrics.steps)", label: "pas", icon: "shoe")
                    metric(value: distanceText, label: "km", icon: "location.fill")
                }
                HStack(spacing: 10) {
                    metric(
                        value: "\(metrics.activeCalories)",
                        label: "kcal",
                        icon: "flame.fill"
                    )
                    metric(
                        value: metrics.heartRate.map { "\($0)" } ?? "—",
                        label: "bpm",
                        icon: "heart.fill"
                    )
                }
                .padding(.top, 4)

                Spacer(minLength: 4)

                Button(role: .destructive, action: onStop) {
                    Label("Arrêter", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private var distanceText: String {
        String(format: "%.2f", metrics.distanceKm)
            .replacingOccurrences(of: ".", with: ",")
    }

    private func metric(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func format(elapsed: TimeInterval) -> String {
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
