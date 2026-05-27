import SwiftUI

/// Pre-walk screen — title, accent walk icon, "Démarrer" CTA.
struct WatchIdleView: View {
    let store: WatchWorkoutStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color("AccentColor"))
            Text("Marche du midi")
                .font(.headline)
            Text("Allons-y dehors,\nmême 10 minutes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                Task { await store.start() }
            } label: {
                Label("Démarrer", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentColor"))
            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
    }
}
