import Combine
import FouleeKit
import SwiftUI

/// Watch home: today's streak + key numbers, and the "Démarrer" CTA. Replaces
/// the old bare idle screen so the watch is useful at a glance, not only
/// mid-session.
///
/// « Démarrer » is pinned to the bottom (ADR 0008) while the rest scrolls: it
/// is what the screen is for, and it used to come after everything else.
///
/// Nothing here names an activity (issue #222): the CTA is the bare verb, and
/// the steps tile carries the footprints glyph — a step count, not a walking
/// figure. The mode does reach this target (`WatchSyncStore`, issue #223), but
/// it decides what Santé records, not how this screen reads.
struct WatchTodayView: View {
    let store: WatchTodayStore
    var errorMessage: String?
    var onStart: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                streakHero
                statsGrid
                if store.hydrationEnabled { WatchHydrationCard(store: store) }
                if !store.isLoading, !store.hasPhoneSync { syncHint }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 2)
        }
        .pinnedAction { WatchStartButton(start: onStart) }
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
                    .scaledSystemFont(size: 20, weight: .bold)
                    .foregroundStyle(.orange)
                Text("\(store.streak)")
                    .scaledNumericFont(size: 34, weight: .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("j")
                    .scaledSystemFont(size: 16, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            Text("série")
                .scaledSystemFont(size: 12)
                .foregroundStyle(.secondary)
        }
        // « 12 j série » read as written says neither « jours » nor what the
        // figure counts (issue #600).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenStreakText(days: store.streak))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statsGrid: some View {
        // One column at the accessibility sizes: two cut « / 10 000 pas » to
        // « / 10 000… » on a 40 mm (issue #600).
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
        return LazyVGrid(columns: columns, spacing: 8) {
            // Steps + minutes show progress toward the phone-synced goals,
            // like the hydration card does; distance/calories have no goal.
            stat(.steps, icon: "shoeprints.fill", tint: MetricPalette.steps,
                 value: Double(store.steps), goal: Double(store.stepsGoal))
            stat(.minutes, icon: "timer", tint: MetricPalette.minutes,
                 value: Double(store.minutes), goal: Double(store.minutesGoal))
            stat(.distance, icon: "ruler.fill", tint: MetricPalette.distance, value: store.distanceKm)
            stat(.calories, icon: "flame.fill", tint: MetricPalette.calories, value: Double(store.calories))
        }
    }

    /// One VoiceOver element per tile, its figures in words: « 8 240 pas sur
    /// 10 000 pas », « 4,2 kilomètres » (issue #600).
    private func stat(_ metric: WalkMetric, icon: String, tint: Color, value: Double, goal: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).scaledSystemFont(size: 13, weight: .bold).foregroundStyle(tint)
            Text(metric.formatted(value))
                .scaledNumericFont(size: 18, weight: .bold).minimumScaleFactor(0.6).lineLimit(1)
            Text(goal.map { "/ \(metric.formatted($0)) \(metric.unit)" } ?? metric.unit)
                .scaledSystemFont(size: 11).foregroundStyle(.secondary)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal.map { metric.spokenText(value, goal: $0) } ?? metric.spokenText(value))
    }

    /// No payload ever received from the phone — explain why the streak and
    /// hydration card are missing instead of hiding them silently.
    private var syncHint: some View {
        Text("Ouvre Foulée sur ton iPhone pour synchroniser")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

/// « Démarrer ». Named rather than inline so a test can find where the home
/// puts it: pinned, outside the scroll (ADR 0008).
struct WatchStartButton: View {
    var start: () -> Void

    var body: some View {
        Button(action: start) {
            Label("Démarrer", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("AccentColor"))
    }
}
