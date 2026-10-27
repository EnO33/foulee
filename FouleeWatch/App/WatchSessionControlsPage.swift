import SwiftUI

/// One page, one job: pause or stop the session (issues #274, #384).
///
/// It carries a clock too, at two thirds the size of the one next door. Not
/// decoration — a page whose only content is a destructive button gives no clue
/// which session it would end. Keeping the elapsed time in view keeps the two
/// pages continuous.
///
/// Laid out as the Exercice app lays its own out (ADR 0008): left of
/// « Séance », two round buttons side by side, « Arrêter » first and « Pause »
/// beside it, each named underneath. A wearer who knows the Exercice app
/// reaches for the same place on the same page.
struct WatchSessionControlsPage: View {
    let metrics: WatchWorkoutMetrics
    var isSaving = false
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchSessionClock(metrics: metrics, size: 22)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 16) {
                    WatchControlButton(
                        title: "Arrêter",
                        systemImage: "xmark",
                        tint: .red,
                        role: .destructive,
                        action: onStop
                    )
                    WatchControlButton(
                        title: metrics.isPaused ? "Reprendre" : "Pause",
                        systemImage: metrics.isPaused ? "play.fill" : "pause.fill",
                        tint: metrics.isPaused ? .green : .yellow,
                        action: onTogglePause
                    )
                }
                // A second tap while the outing saves would read as « it did
                // not work » (issue #380): the store ignores it, and so does this.
                .disabled(isSaving)
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
        }
        .accessibilityLabel("Contrôles")
    }
}

/// A round control with its name underneath, the shape of the Exercice app's
/// own (ADR 0008). Shared by the wrist's session and the phone's.
///
/// The button is named for VoiceOver and the caption hidden from it, so the
/// control reads once, as « Arrêter », and a UI test finds it by that name.
struct WatchControlButton: View {
    var title: LocalizedStringResource
    var systemImage: String
    var tint: Color
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(role: role, action: action) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                    .frame(width: 52, height: 52)
            }
            .buttonBorderShape(.circle)
            .tint(tint)
            .accessibilityLabel(Text(title))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Shown over the session from the tap on « Arrêter » until the summary
/// (issue #380): ending the workout and writing it, route included, to Santé
/// takes a few seconds, and a screen that does not move in the meantime reads
/// as a tap that was missed.
struct WatchSavingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Enregistrement…")
                .font(.headline)
            Text("Ta sortie part dans Santé")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
        .accessibilityElement(children: .combine)
    }
}
