import FouleeKit
import SwiftUI
import WidgetKit

/// iPhone widget showing the current streak. Supports the three Lock
/// Screen accessory families (matches what we already ship on the Watch)
/// plus the two most useful Home Screen sizes (`.systemSmall` and
/// `.systemMedium`).
///
/// Wires its own `StreakSnapshotProvider` (the Watch target has a separate
/// `StreakProvider` reading `WatchSyncStore`); both follow the shared
/// `WidgetRefresh` cadence so the two surfaces move together.
/// Reads the current streak from the snapshot the app writes to the app group
/// (no HealthKit in the widget, so it still works while the phone is locked).
struct StreakSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(WidgetRefresh.nextRefresh(after: .now))))
    }

    private func entry() -> StreakEntry {
        let snapshot = SharedStore.read()
        return StreakEntry(
            date: .now,
            streak: snapshot?.streak ?? 0,
            activityMode: snapshot?.activityMode ?? .walking
        )
    }
}

struct StreakWidget: Widget {
    static let kind = "com.eno33.foulee.streakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StreakSnapshotProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(StreakWidget.containerBackground, for: .widget)
        }
        .configurationDisplayName("Série Foulée")
        // Gallery text is compile-time: it cannot follow the activity
        // preference, so it has to be true for a walker *and* a runner
        // (issue #222). "bougé" is the one verb that covers both, and it is
        // also what the streak actually counts — active minutes, whatever
        // produced them.
        .description("Le nombre de jours d'affilée où tu as bougé.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall,
            .systemMedium
        ])
    }

    fileprivate static let containerBackground = LinearGradient(
        colors: [
            Color(red: 0x2A / 255, green: 0x0A / 255, blue: 0x4A / 255),
            Color(red: 0x1A / 255, green: 0x0A / 255, blue: 0x3A / 255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct StreakWidgetView: View {
    /// The activity figure, following the user's mode exactly as the app's own
    /// Today ring does (issue #222): the snapshot in the app group carries
    /// `activityMode`, written by the same pass that publishes it to the Watch.
    /// A walker keeps `figure.walk` — the glyph this widget always showed —
    /// and only a runner gets a runner.
    private var activityIcon: String { entry.activityMode.icon }

    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        // The medium size summarises only its figure: the tagline and the
        // encouragement beside it read as written.
        if family == .systemMedium {
            systemMediumView
        } else {
            compactView.widgetSummary(spokenStreak)
        }
    }

    @ViewBuilder private var compactView: some View {
        switch family {
        case .accessoryCircular: accessoryCircularView
        case .accessoryRectangular: accessoryRectangularView
        case .systemSmall: systemSmallView
        default: accessoryInlineView
        }
    }

    /// « Série de 12 jours » (issue #601): the flame, the bare « 12 » and « j »
    /// were three elements, and « j » is read as a letter.
    private var spokenStreak: Text { Text(spokenStreakText(days: entry.streak)) }

    // MARK: - Lock Screen (accessory families)

    private var accessoryCircularView: some View {
        VStack(spacing: 0) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
                .widgetAccentable()
            Text("\(entry.streak)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("j")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var accessoryRectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.orange)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.streak) j")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("série Foulée")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessoryInlineView: some View {
        Label("\(entry.streak) j d'affilée", systemImage: "flame.fill")
    }

    // MARK: - Home Screen (system families)

    private var systemSmallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: activityIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.orange)
                    .widgetAccentable()
            }
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.streak)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(daysInARow)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var systemMediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.orange)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text("\(entry.streak)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(daysInARow)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .widgetSummary(spokenStreak)
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: 1)
            VStack(alignment: .leading, spacing: 6) {
                Label("Foulée", systemImage: activityIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Bouge un peu, chaque jour.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
                Text(streakCopy)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Under the big figure, which it does not repeat: a catalog plural must
    /// show its number, hence two strings.
    private var daysInARow: LocalizedStringResource {
        entry.streak == 1 ? "jour d'affilée" : "jours d'affilée"
    }

    private var streakCopy: LocalizedStringResource {
        switch entry.streak {
        case 0: "C'est l'occasion de démarrer une série."
        case 1...4: "Continue, le rythme se prend."
        case 5...13: "Belle constance — garde le cap."
        default: "Tu tiens un sacré rythme. Bravo."
        }
    }
}
