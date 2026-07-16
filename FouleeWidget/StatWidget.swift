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
    /// When the value was actually read (HealthKit or snapshot) — shown as a
    /// live relative stamp so staleness is visible without a reload.
    let fetchedAt: Date

    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: WidgetTimelineBuilder.relevanceScore(at: date))
    }
}

/// Reads the chosen stat from the snapshot the app writes to the app group.
struct StatProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatEntry {
        StatEntry(date: .now, metric: .steps, value: 0, goal: 6_000, fetchedAt: .now)
    }

    func snapshot(for configuration: StatWidgetIntent, in context: Context) async -> StatEntry {
        entry(for: configuration.metric)
    }

    func timeline(for configuration: StatWidgetIntent, in context: Context) async -> Timeline<StatEntry> {
        // Live HealthKit when unlocked, snapshot fallback when locked.
        // Daytime cadence — see WidgetRefresh.
        let snapshot = await WidgetLiveMetrics.freshSnapshot()
        // One clock sample for entries, reset and policy, so a rebuild
        // straddling midnight cannot pair stale totals with a reset dated
        // the *following* midnight.
        let now = Date.now
        let nextRefresh = WidgetRefresh.nextRefresh(after: now)
        let midnight = WidgetRefresh.nextMidnight(after: now)
        // Interpolated future entries until the next reload slot — steps and
        // minutes projected, distance and calories flat. Same single
        // getTimeline call, so the reload budget is unchanged.
        var entries = WidgetTimelineBuilder
            .projectedValues(counters: snapshot.counters, now: now, nextRefresh: nextRefresh, nextMidnight: midnight)
            .map { Self.entry(for: configuration.metric, projecting: $0, goals: snapshot, fetchedAt: now) }
        // Pre-rendered zero entry at local midnight — the system swaps to it
        // at 00:00 without a reload, so the stat never shows yesterday.
        let reset = StatEntry(
            date: midnight, metric: configuration.metric,
            value: 0, goal: entries.first?.goal ?? 0, fetchedAt: midnight
        )
        entries.append(reset)
        return Timeline(entries: entries, policy: .after(nextRefresh))
    }

    private func entry(for metric: StatMetric) -> StatEntry {
        let snapshot = (SharedStore.read() ?? .placeholder).zeroedIfStale()
        let now = Date.now
        return Self.entry(
            for: metric, projecting: WidgetTimelineBuilder.point(counters: snapshot.counters, at: now),
            goals: snapshot, fetchedAt: now
        )
    }

    private static func entry(
        for metric: StatMetric,
        projecting value: WidgetProjectedValue,
        goals snapshot: WidgetSnapshot,
        fetchedAt: Date
    ) -> StatEntry {
        switch metric {
        case .steps:
            StatEntry(date: value.date, metric: metric, value: Double(value.steps),
                      goal: Double(snapshot.stepsGoal), fetchedAt: fetchedAt)
        case .minutes:
            StatEntry(date: value.date, metric: metric, value: Double(value.minutes),
                      goal: Double(snapshot.minutesGoal), fetchedAt: fetchedAt)
        case .distance:
            StatEntry(date: value.date, metric: metric, value: value.distanceKm, goal: 0, fetchedAt: fetchedAt)
        case .calories:
            StatEntry(date: value.date, metric: metric, value: Double(value.calories), goal: 0, fetchedAt: fetchedAt)
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
                FreshnessStamp(fetchedAt: entry.fetchedAt).foregroundStyle(.secondary)
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
            FreshnessStamp(fetchedAt: entry.fetchedAt).foregroundStyle(.white.opacity(0.5))
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
        entry.metric == .distance ? entry.value.decimalComma() : Int(entry.value).formatted()
    }

    private var goalText: String {
        entry.metric == .distance ? entry.goal.decimalComma() : Int(entry.goal).formatted()
    }

    /// Shorter form for the tight Lock Screen circle (e.g. `4,2k`).
    private var compactValue: String {
        switch entry.metric {
        case .steps, .calories:
            entry.value >= 1_000 ? (entry.value / 1_000).decimalComma() + "k" : "\(Int(entry.value))"
        case .minutes: "\(Int(entry.value))"
        case .distance: entry.value.decimalComma()
        }
    }
}
