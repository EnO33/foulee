@preconcurrency import HealthKit
import SwiftUI
import WidgetKit

/// Today's water intake vs goal as a teal ring on the watch face. Tapping it
/// opens the watch app, whose home has the hydration card and its "J'ai bu"
/// button. Water comes from the watch's HealthKit (today's data is local);
/// the goal comes from the phone-synced payload in the shared app group.
struct WatchHydrationComplication: Widget {
    static let kind = "com.eno33.foulee.watchHydrationComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchHydrationProvider()) { entry in
            WatchHydrationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hydratation")
        .description("Ton eau bue du jour, par rapport à ton objectif.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WatchHydrationEntry: TimelineEntry, Sendable {
    let date: Date
    let waterML: Int
    let goalML: Int

    static let placeholder = WatchHydrationEntry(date: .now, waterML: 0, goalML: 2_000)
}

struct WatchHydrationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchHydrationEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchHydrationEntry) -> Void) {
        let box = UncheckedSendableBox(completion)
        Task { box.value(await Self.entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchHydrationEntry>) -> Void) {
        let box = UncheckedSendableBox(completion)
        Task {
            let entry = await Self.entry()
            box.value(Timeline(entries: [entry], policy: .after(WidgetRefresh.nextRefresh(after: .now))))
        }
    }

    private static func entry() async -> WatchHydrationEntry {
        WatchHydrationEntry(
            date: .now,
            waterML: await todayWaterML(),
            goalML: WatchSyncStore.read()?.hydrationGoalML ?? 2_000
        )
    }

    private static func todayWaterML() async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let store = HKHealthStore()
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.dietaryWater),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let milliliters = statistics?.sumQuantity()?.doubleValue(for: .literUnit(with: .milli)) ?? 0
                continuation.resume(returning: Int(milliliters))
            }
            store.execute(query)
        }
    }
}

struct WatchHydrationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchHydrationEntry

    private var progress: Double {
        entry.goalML > 0 ? min(Double(entry.waterML) / Double(entry.goalML), 1) : 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: inline
        }
    }

    private var circular: some View {
        Gauge(
            value: progress,
            label: { Image(systemName: "drop.fill") },
            currentValueLabel: {
                Text(litres(entry.waterML)).minimumScaleFactor(0.5)
            }
        )
        .gaugeStyle(.accessoryCircular)
        .tint(.teal)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(litres(entry.waterML)) / \(litres(entry.goalML)) L")
                    .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                Text("hydratation")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inline: some View {
        Label("\(litres(entry.waterML)) / \(litres(entry.goalML)) L", systemImage: "drop.fill")
    }
}
