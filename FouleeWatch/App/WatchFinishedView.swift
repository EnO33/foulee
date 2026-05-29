import SwiftUI

/// Post-walk summary — quick recap + a button to clear the slate.
struct WatchFinishedView: View {
    let metrics: WatchWorkoutMetrics
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Color("AccentColor"))
            Text("Bravo")
                .font(.headline)
            VStack(spacing: 2) {
                Text(metrics.elapsed.walkClockText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("\(metrics.steps) pas · \(metrics.distanceKm.kmText())")
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
}
