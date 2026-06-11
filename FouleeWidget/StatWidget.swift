import AppIntents
import SwiftUI
import WidgetKit

/// Which daily stat a configurable Stat widget shows. Picked per-widget, so
/// the user can drop one as a step "pedometer" and others for distance,
/// calories or activity minutes.
enum StatMetric: String, AppEnum {
    case steps
    case minutes
    case distance
    case calories

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Statistique")
    }

    static var caseDisplayRepresentations: [StatMetric: DisplayRepresentation] {
        [
            .steps: DisplayRepresentation(title: "Pas"),
            .minutes: DisplayRepresentation(title: "Activité"),
            .distance: DisplayRepresentation(title: "Distance"),
            .calories: DisplayRepresentation(title: "Calories")
        ]
    }
}

struct StatWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Statistique Foulée" }
    static var description: IntentDescription { "Choisis la donnée du jour à afficher." }

    @Parameter(title: "Donnée", default: .steps)
    var metric: StatMetric
}

struct StatEntry: TimelineEntry {
    let date: Date
    let metric: StatMetric
    let value: Double
    let goal: Double
}

/// Reads the chosen stat from the snapshot the app writes to the app group.
struct StatProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatEntry {
        StatEntry(date: .now, metric: .steps, value: 0, goal: 6_000)
    }

    func snapshot(for configuration: StatWidgetIntent, in context: Context) async -> StatEntry {
        entry(for: configuration.metric)
    }

    func timeline(for configuration: StatWidgetIntent, in context: Context) async -> Timeline<StatEntry> {
        // Live HealthKit when unlocked, snapshot fallback when locked.
        let entry = Self.entry(for: configuration.metric, from: await WidgetLiveMetrics.freshSnapshot())
        return Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 20 * 60)))
    }

    private func entry(for metric: StatMetric) -> StatEntry {
        Self.entry(for: metric, from: SharedStore.read() ?? .placeholder)
    }

    private static func entry(for metric: StatMetric, from snapshot: WidgetSnapshot) -> StatEntry {
        switch metric {
        case .steps:
            return StatEntry(date: .now, metric: metric, value: Double(snapshot.steps), goal: Double(snapshot.stepsGoal))
        case .minutes:
            return StatEntry(date: .now, metric: metric, value: Double(snapshot.minutes), goal: Double(snapshot.minutesGoal))
        case .distance:
            return StatEntry(date: .now, metric: metric, value: snapshot.distanceKm, goal: 0)
        case .calories:
            return StatEntry(date: .now, metric: metric, value: Double(snapshot.calories), goal: 0)
        }
    }
}

struct StatWidget: Widget {
    static let kind = "com.eno33.foulee.statWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: StatWidgetIntent.self, provider: StatProvider()) { entry in
            StatWidgetView(entry: entry)
                .containerBackground(Self.containerBackground, for: .widget)
        }
        .configurationDisplayName("Statistique Foulée")
        .description("Une donnée du jour : pas, activité, distance ou calories.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }

    static let containerBackground = LinearGradient(
        colors: [Color(red: 0x2A / 255, green: 0x0A / 255, blue: 0x4A / 255),
                 Color(red: 0x1A / 255, green: 0x0A / 255, blue: 0x3A / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct StatWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemSmall: small
        default: inline
        }
    }

    private var circular: some View {
        Group {
            if hasGoal {
                Gauge(
                    value: progress,
                    label: { Image(systemName: icon) },
                    currentValueLabel: { Text(compactValue).minimumScaleFactor(0.5) }
                )
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: icon).font(.system(size: 11, weight: .bold))
                        Text(compactValue).font(.system(size: 15, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.5)
                    }
                }
            }
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text(valueText + (hasGoal ? " / \(goalText)" : ""))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var inline: some View {
        Label("\(valueText) \(unit)", systemImage: icon)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(tint)
                Spacer()
                if hasGoal {
                    Text("/ \(goalText)").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                }
            }
            Spacer(minLength: 4)
            Text(valueText)
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .foregroundStyle(.white)
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    // MARK: - Per-metric formatting

    private var hasGoal: Bool { entry.goal > 0 }
    private var progress: Double { entry.goal > 0 ? min(entry.value / entry.goal, 1) : 0 }

    private var icon: String {
        switch entry.metric {
        case .steps: "shoeprints.fill"
        case .minutes: "timer"
        case .distance: "ruler.fill"
        case .calories: "flame.fill"
        }
    }

    private var unit: String {
        switch entry.metric {
        case .steps: "pas"
        case .minutes: "min"
        case .distance: "km"
        case .calories: "kcal"
        }
    }

    private var label: String {
        switch entry.metric {
        case .steps: "pas aujourd'hui"
        case .minutes: "min d'activité"
        case .distance: "kilomètres"
        case .calories: "calories"
        }
    }

    private var tint: Color {
        switch entry.metric {
        case .steps: Color(red: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255)
        case .minutes: Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
        case .distance: Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
        case .calories: Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
        }
    }

    private var valueText: String {
        entry.metric == .distance ? distanceString(entry.value) : Int(entry.value).formatted()
    }

    private var goalText: String {
        entry.metric == .distance ? distanceString(entry.goal) : Int(entry.goal).formatted()
    }

    /// Shorter form for the tight Lock Screen circle (e.g. `4,2k`).
    private var compactValue: String {
        switch entry.metric {
        case .steps, .calories:
            entry.value >= 1_000 ? distanceString(entry.value / 1_000) + "k" : "\(Int(entry.value))"
        case .minutes: "\(Int(entry.value))"
        case .distance: distanceString(entry.value)
        }
    }

    private func distanceString(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
