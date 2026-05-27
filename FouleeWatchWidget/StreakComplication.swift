import SwiftUI
import WidgetKit

/// Foulée's streak complication — shows up on the watch face in three
/// families:
/// - circular: small pill with a flame and the streak number
/// - rectangular: flame icon + number + caption
/// - inline: text-only line "🔥 12 j"
struct StreakComplication: Widget {
    static let kind = "com.eno33.foulee.streakComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StreakProvider()) { entry in
            StreakComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Série")
        .description("Le nombre de jours d'affilée où tu as marché.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct StreakComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline: inlineView
        default: inlineView
        }
    }

    private var circularView: some View {
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

    private var rectangularView: some View {
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

    private var inlineView: some View {
        Label("\(entry.streak) j d'affilée", systemImage: "flame.fill")
    }
}
