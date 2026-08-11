import SwiftUI

/// The hydration card: intake against the goal, and « J'ai bu ».
///
/// Extracted from `WatchTodayView` so the home and the session's own hydration
/// page draw the same card rather than two that drift (issue #281). It is one
/// view over one store, so « J'ai bu » behaves identically wherever it is
/// tapped — which matters, because the interesting tap is the one that happens
/// mid-outing.
struct WatchHydrationCard: View {
    let store: WatchTodayStore

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.teal)
                Text("\(litres(store.waterML)) / \(litres(store.hydrationGoalML)) L")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
            }
            ProgressView(value: progress).tint(.teal)
            if store.waterDenied {
                // Writing water was denied — a dead "J'ai bu" button would be
                // indistinguishable from a sync bug.
                Text("Autorise l'eau dans Santé")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Button {
                    Task { await store.logGlass() }
                } label: {
                    Label("J'ai bu", systemImage: "drop.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
            if let hydrationError = store.hydrationError {
                Text(hydrationError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sensoryFeedback(.increase, trigger: store.waterML)
    }

    private var progress: Double {
        guard store.hydrationGoalML > 0 else { return 0 }
        return min(Double(store.waterML) / Double(store.hydrationGoalML), 1)
    }
}
