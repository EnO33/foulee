import SwiftUI

/// Post-walk summary — quick recap + a button to clear the slate.
struct WatchFinishedView: View {
    let metrics: WatchWorkoutMetrics
    var onDone: () -> Void

    private var distanceText: String {
        String(format: "%.2f km", metrics.distanceKm)
            .replacingOccurrences(of: ".", with: ",")
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Color("AccentColor"))
            Text("Bravo")
                .font(.headline)
            VStack(spacing: 2) {
                Text(format(elapsed: metrics.elapsed))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("\(metrics.steps) pas · \(distanceText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDone) {
                Text("Terminer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentColor"))
        }
        .padding(.horizontal, 8)
    }

    private func format(elapsed: TimeInterval) -> String {
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
