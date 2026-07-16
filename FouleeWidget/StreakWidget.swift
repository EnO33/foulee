import SwiftUI
import WidgetKit

/// iPhone widget showing the current walk streak. Supports the three Lock
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
        StreakEntry(date: .now, streak: SharedStore.read()?.streak ?? 0)
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
        .description("Le nombre de jours d'affilée où tu as marché.")
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
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        switch family {
        case .accessoryCircular: accessoryCircularView
        case .accessoryRectangular: accessoryRectangularView
        case .accessoryInline: accessoryInlineView
        case .systemSmall: systemSmallView
        case .systemMedium: systemMediumView
        default: accessoryInlineView
        }
    }

    // MARK: - Lock Screen (accessory families)

    private var accessoryCircularView: some View {
        VStack(spacing: 0) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
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
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.streak)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("jours d'affilée")
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
                Spacer(minLength: 0)
                Text("\(entry.streak)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("jours d'affilée")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: 1)
            VStack(alignment: .leading, spacing: 6) {
                Label("Foulée", systemImage: "figure.walk.motion")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Marche du midi")
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

    private var streakCopy: String {
        switch entry.streak {
        case 0: "C'est l'occasion de démarrer une série."
        case 1...4: "Continue, le rythme se prend."
        case 5...13: "Belle constance — garde le cap."
        default: "Tu tiens un sacré rythme. Bravo."
        }
    }
}
