import Combine
import SwiftUI

/// Watch home: today's streak + key numbers, and the "Démarrer" CTA. Replaces
/// the old bare idle screen so the watch is useful at a glance, not only
/// mid-session.
///
/// Nothing here names an activity (issue #222): the CTA is the bare verb, and
/// the steps tile carries the footprints glyph — a step count, not a walking
/// figure. The mode does reach this target (`WatchSyncStore`, issue #223), but
/// it decides what Santé records, not how this screen reads.
struct WatchTodayView: View {
    let store: WatchTodayStore
    var errorMessage: String?
    var onStart: () -> Void
    /// Opens the device probe (issue #248).
    var onDiagnostic: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                streakHero
                statsGrid
                if store.hydrationEnabled { hydrationCard }
                startButton
                if !store.isLoading, !store.hasPhoneSync { syncHint }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                diagnosticSection
            }
            .padding(.horizontal, 2)
        }
        .task {
            store.startObserving()
            await store.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchSyncReceived)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: HydrationNotification.actionHandled)) { _ in
            // A glass logged from the hydration banner — re-read so the card
            // and its haptic reflect it.
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
            // Steps + minutes show progress toward the phone-synced goals,
            // like the hydration card does; distance/calories have no goal.
            stat(icon: "shoeprints.fill", tint: .purple,
                 value: store.steps.formatted(), goal: store.stepsGoal.formatted(), label: "pas")
            stat(icon: "timer", tint: .green,
                 value: "\(store.minutes)", goal: "\(store.minutesGoal)", label: "min")
            stat(icon: "ruler.fill", tint: .blue, value: kmText, label: "km")
            stat(icon: "flame.fill", tint: .orange, value: "\(store.calories)", label: "kcal")
        }
    }

    private func stat(icon: String, tint: Color, value: String, goal: String? = nil, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text(goal.map { "/ \($0) \(label)" } ?? label)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var hydrationProgress: Double {
        guard store.hydrationGoalML > 0 else { return 0 }
        return min(Double(store.waterML) / Double(store.hydrationGoalML), 1)
    }

    private var hydrationCard: some View {
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
            ProgressView(value: hydrationProgress).tint(.teal)
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

    /// No payload ever received from the phone — explain why the streak and
    /// hydration card are missing instead of hiding them silently.
    private var syncHint: some View {
        Text("Ouvre Foulée sur ton iPhone pour synchroniser")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
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

    /// « Diagnostic » (issue #248) — a labelled section, last on the home
    /// screen, below the CTA and any error line.
    ///
    /// Last on purpose: the home screen is read at a glance outdoors, and a
    /// developer instrument must not sit between the streak and « Démarrer ».
    /// Findable on purpose too — no long press, no hidden gesture: the owner
    /// has to reach it mid-outing, on a wrist, and a secret gesture is one
    /// more thing to remember while cold. It ships in **Release** because
    /// TestFlight is the only route onto a paired Apple Watch and TestFlight
    /// distributes Release; a `#if DEBUG` screen would not be there at all.
    private var diagnosticSection: some View {
        VStack(spacing: 3) {
            WatchDiagnosticButton(open: onDiagnostic)
            Text("Capteur de mouvement")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private var kmText: String {
        store.distanceKm.decimalComma()
    }
}
