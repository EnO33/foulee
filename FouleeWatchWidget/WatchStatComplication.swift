@preconcurrency import HealthKit
import AppIntents
import SwiftUI
import WidgetKit

/// A configurable watch complication: pick the metric (pas, activité, distance,
/// calories) per instance — a pedometer on the wrist, or any of today's stats.
/// Reads HealthKit on the watch (auth inherited from the app).
enum WatchStatMetric: String, AppEnum {
    case steps
    case minutes
    case distance
    case calories

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Statistique")
    }

    static var caseDisplayRepresentations: [WatchStatMetric: DisplayRepresentation] {
        [
            .steps: DisplayRepresentation(title: "Pas"),
            .minutes: DisplayRepresentation(title: "Activité"),
            .distance: DisplayRepresentation(title: "Distance"),
            .calories: DisplayRepresentation(title: "Calories")
        ]
    }

    var identifier: HKQuantityTypeIdentifier {
        switch self {
        case .steps: .stepCount
        case .minutes: .appleExerciseTime
        case .distance: .distanceWalkingRunning
        case .calories: .activeEnergyBurned
        }
    }

    var unit: HKUnit {
        switch self {
        case .steps: .count()
        case .minutes: .minute()
        case .distance: .meter()
        case .calories: .kilocalorie()
        }
    }

    /// Goal for the circular gauge (steps/minutes only; 0 = no gauge).
    var goal: Double {
        switch self {
        case .steps: 6_000
        case .minutes: 20
        case .distance, .calories: 0
        }
    }

    var icon: String {
        switch self {
        case .steps: "shoeprints.fill"
        case .minutes: "timer"
        case .distance: "ruler.fill"
        case .calories: "flame.fill"
        }
    }

    var unitLabel: String {
        switch self {
        case .steps: "pas"
        case .minutes: "min"
        case .distance: "km"
        case .calories: "kcal"
        }
    }

    var name: String {
        switch self {
        case .steps: "Pas"
        case .minutes: "Activité"
        case .distance: "Distance"
        case .calories: "Calories"
        }
    }
}

struct WatchStatIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Statistique Foulée" }
    static var description: IntentDescription { "Choisis la donnée du jour à afficher." }

    @Parameter(title: "Donnée", default: .steps)
    var metric: WatchStatMetric
}

struct WatchStatEntry: TimelineEntry {
    let date: Date
    let metric: WatchStatMetric
    let value: Double

    static let placeholder = WatchStatEntry(date: .now, metric: .steps, value: 0)
}

struct WatchStatProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WatchStatEntry { .placeholder }

    func snapshot(for configuration: WatchStatIntent, in context: Context) async -> WatchStatEntry {
        await entry(for: configuration.metric)
    }

    func timeline(for configuration: WatchStatIntent, in context: Context) async -> Timeline<WatchStatEntry> {
        let metric = configuration.metric
        let live = await Self.queriedTodaySum(for: metric)
        if let live { WatchComplicationCache.write(live, for: metric.rawValue) }
        // Query failed (protected data after a reboot, transient error):
        // today's last known value instead of a fake zero.
        let value = live ?? WatchComplicationCache.read(for: metric.rawValue) ?? 0
        let now = Date.now
        let nextRefresh = WidgetRefresh.nextRefresh(after: now)
        let midnight = WidgetRefresh.nextMidnight(after: now)
        // Interpolated future entries until the next reload slot — steps
        // projected (clamped below the gauge's own goal so a crossing is
        // never fabricated), the other metrics re-dated flat. Still one
        // timeline call per slot: more entries, not more reloads.
        // A cached fallback is never projected: "last known value" means
        // exactly that, not a fabricated progression from a count that may
        // be hours old — the builder then only provides the re-dated grid.
        let counters = live == nil
            ? WidgetCounters(steps: 0, stepsGoal: 0, minutes: 0, minutesGoal: 0)
            : Self.counters(for: metric, value: value)
        var entries = WidgetTimelineBuilder
            .projectedValues(
                counters: counters,
                now: now, nextRefresh: nextRefresh, nextMidnight: midnight
            )
            .map { point in
                WatchStatEntry(
                    date: point.date, metric: metric,
                    value: live == nil ? value : Self.value(for: metric, from: point)
                )
            }
        // Pre-rendered zero entry at local midnight — the system swaps to it
        // at 00:00 without a reload, so the complication never shows
        // yesterday's total overnight.
        entries.append(WatchStatEntry(date: midnight, metric: metric, value: 0))
        return Timeline(entries: entries, policy: .after(nextRefresh))
    }

    /// Routes the single queried value into the projection slot matching the
    /// metric. Only steps get a moving projection; minutes would need the
    /// steps pace (a second HealthKit query) to be honest, so they stay flat
    /// like distance and calories.
    private static func counters(for metric: WatchStatMetric, value: Double) -> WidgetCounters {
        switch metric {
        case .steps:
            WidgetCounters(steps: Int(value), stepsGoal: Int(metric.goal), minutes: 0, minutesGoal: 0)
        case .minutes:
            WidgetCounters(steps: 0, stepsGoal: 0, minutes: Int(value), minutesGoal: Int(metric.goal))
        case .distance:
            WidgetCounters(steps: 0, stepsGoal: 0, minutes: 0, minutesGoal: 0, distanceKm: value)
        case .calories:
            WidgetCounters(steps: 0, stepsGoal: 0, minutes: 0, minutesGoal: 0, calories: Int(value))
        }
    }

    private static func value(for metric: WatchStatMetric, from point: WidgetProjectedValue) -> Double {
        switch metric {
        case .steps: Double(point.steps)
        case .minutes: Double(point.minutes)
        case .distance: point.distanceKm
        case .calories: Double(point.calories)
        }
    }

    /// watchOS requires recommendations so the metric variants appear in the
    /// complication gallery (one preconfigured entry per metric).
    func recommendations() -> [AppIntentRecommendation<WatchStatIntent>] {
        [WatchStatMetric.steps, .minutes, .distance, .calories].map { metric in
            let intent = WatchStatIntent()
            intent.metric = metric
            return AppIntentRecommendation(intent: intent, description: Text(metric.name))
        }
    }

    private func entry(for metric: WatchStatMetric) async -> WatchStatEntry {
        WatchStatEntry(date: .now, metric: metric, value: await Self.todaySum(for: metric))
    }

    private static func todaySum(for metric: WatchStatMetric) async -> Double {
        guard let live = await queriedTodaySum(for: metric) else {
            // Query failed (protected data after a reboot, transient error):
            // show today's last known value instead of a fake zero.
            return WatchComplicationCache.read(for: metric.rawValue) ?? 0
        }
        WatchComplicationCache.write(live, for: metric.rawValue)
        return live
    }

    /// nil means the query failed — distinct from a legitimate zero, so the
    /// caller knows when the cache fallback is allowed.
    private static func queriedTodaySum(for metric: WatchStatMetric) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let store = HKHealthStore()
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(metric.identifier),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let statistics {
                    continuation.resume(returning: statistics.sumQuantity()?.doubleValue(for: metric.unit) ?? 0)
                } else if (error as? HKError)?.code == .errorNoData {
                    // No samples today is a legitimate zero, not a failure.
                    continuation.resume(returning: 0)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }
}

struct WatchStatComplication: Widget {
    static let kind = "com.eno33.foulee.watchStatComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: WatchStatIntent.self, provider: WatchStatProvider()) { entry in
            WatchStatComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Statistique")
        .description("Une donnée du jour : pas, activité, distance ou calories.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WatchStatComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchStatEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: inline
        }
    }

    private var circular: some View {
        Group {
            if entry.metric.goal > 0 {
                Gauge(
                    value: min(entry.value / entry.metric.goal, 1),
                    label: { Image(systemName: entry.metric.icon) },
                    currentValueLabel: { Text(compactValue).minimumScaleFactor(0.5) }
                )
                .gaugeStyle(.accessoryCircular)
            } else {
                VStack(spacing: 1) {
                    Image(systemName: entry.metric.icon).font(.system(size: 12, weight: .bold))
                    Text(compactValue).font(.system(size: 15, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                }
            }
        }
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.metric.icon).font(.system(size: 20, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text(valueText)
                    .font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                Text(entry.metric.unitLabel).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var inline: some View {
        Label("\(valueText) \(entry.metric.unitLabel)", systemImage: entry.metric.icon)
    }

    private var valueText: String {
        entry.metric == .distance ? entry.value.decimalComma() : Int(entry.value).formatted()
    }

    private var compactValue: String {
        switch entry.metric {
        case .steps, .calories:
            entry.value >= 1_000 ? (entry.value / 1_000).decimalComma() + "k" : "\(Int(entry.value))"
        case .minutes: "\(Int(entry.value))"
        case .distance: entry.value.decimalComma()
        }
    }
}
