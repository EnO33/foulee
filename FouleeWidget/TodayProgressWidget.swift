import SwiftUI
import WidgetKit

/// Today's two daily goals at a glance — steps and activity minutes — as a
/// double progress ring. On the Lock Screen (accessory families) the system
/// renders it monochrome, so the two goals read as two concentric arcs; on the
/// Home Screen they keep their colours (purple steps, green activity).
struct TodayProgressWidget: Widget {
    static let kind = WidgetKind.today

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            TodayProgressView(entry: entry)
                .containerBackground(Self.containerBackground, for: .widget)
        }
        .configurationDisplayName("Aujourd'hui Foulée")
        .description("Tes pas et tes minutes d'activité du jour, par rapport à tes objectifs.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }

    static let stepsGradient = LinearGradient(
        colors: [Color(red: 0xD9 / 255, green: 0x7A / 255, blue: 0xFF / 255),
                 Color(red: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255),
                 Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let minutesGradient = LinearGradient(
        colors: [Color(red: 0x5B / 255, green: 0xE3 / 255, blue: 0x6B / 255),
                 Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255),
                 Color(red: 0x1F / 255, green: 0xA8 / 255, blue: 0x45 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let containerBackground = LinearGradient(
        colors: [Color(red: 0x2A / 255, green: 0x0A / 255, blue: 0x4A / 255),
                 Color(red: 0x1A / 255, green: 0x0A / 255, blue: 0x3A / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// One day's progress toward both goals.
struct TodayEntry: TimelineEntry, Sendable {
    let date: Date
    let steps: Int
    let stepsGoal: Int
    let minutes: Int
    let minutesGoal: Int
    /// When the values were actually read (HealthKit or snapshot) — shown as
    /// a live relative stamp so staleness is visible without a reload.
    let fetchedAt: Date

    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: WidgetTimelineBuilder.relevanceScore(at: date))
    }

    static let placeholder = TodayEntry(
        date: .now, steps: 0, stepsGoal: 6_000, minutes: 0, minutesGoal: 20, fetchedAt: .now
    )
}

/// Reads today's progress from the snapshot the app writes to the app group
/// (no HealthKit in the widget, so it still works while the phone is locked).
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // Refresh from HealthKit when the phone is unlocked so the rings move
        // without opening the app; fall back to the snapshot when locked.
        // Daytime cadence concentrates the refresh budget on waking hours;
        // water/workouts already push instantly via background delivery.
        let box = UncheckedSendableBox(completion)
        Task {
            let snapshot = await WidgetLiveMetrics.freshSnapshot()
            // One clock sample for entries, reset and policy, so a rebuild
            // straddling midnight cannot pair stale totals with a reset
            // dated the *following* midnight.
            let now = Date.now
            box.value(Self.timeline(from: snapshot, now: now))
        }
    }

    /// The whole batch — now, interpolated future points, midnight reset —
    /// comes from this one getTimeline call: more entries, not more reloads,
    /// so the daily budget stays where WidgetRefresh put it.
    private static func timeline(from snapshot: WidgetSnapshot, now: Date) -> Timeline<TodayEntry> {
        let nextRefresh = WidgetRefresh.nextRefresh(after: now)
        let midnight = WidgetRefresh.nextMidnight(after: now)
        var entries = WidgetTimelineBuilder
            .projectedValues(counters: snapshot.counters, now: now, nextRefresh: nextRefresh, nextMidnight: midnight)
            .map { entry(from: $0, goals: snapshot, fetchedAt: now) }
        // Pre-rendered zero entry at local midnight: the system swaps to it
        // at 00:00 without a reload, so the rings never show yesterday's
        // totals overnight.
        entries.append(TodayEntry(
            date: midnight, steps: 0, stepsGoal: snapshot.stepsGoal,
            minutes: 0, minutesGoal: snapshot.minutesGoal, fetchedAt: midnight
        ))
        return Timeline(entries: entries, policy: .after(nextRefresh))
    }

    private func entry() -> TodayEntry {
        let snapshot = (SharedStore.read() ?? .placeholder).zeroedIfStale()
        let now = Date.now
        return Self.entry(from: WidgetTimelineBuilder.point(counters: snapshot.counters, at: now), goals: snapshot, fetchedAt: now)
    }

    private static func entry(from value: WidgetProjectedValue, goals: WidgetSnapshot, fetchedAt: Date) -> TodayEntry {
        TodayEntry(
            date: value.date,
            steps: value.steps,
            stepsGoal: goals.stepsGoal,
            minutes: value.minutes,
            minutesGoal: goals.minutesGoal,
            fetchedAt: fetchedAt
        )
    }
}

struct TodayProgressView: View {
    /// The steps line gets the footprints glyph rather than a walking figure
    /// (issue #222): it labels a step count, which a run produces just as well,
    /// and it is already what `StatWidget` and the watch's Today grid use for
    /// the same number.
    private static let stepsIcon = "shoeprints.fill"
    /// Neutral activity glyph for the circular family, where the symbol stands
    /// for the app rather than for a metric. Literal because `FouleeIcon` is
    /// not compiled into this target (see Project.swift).
    private static let activityIcon = "figure.mixed.cardio"

    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var stepsProgress: Double {
        entry.stepsGoal > 0 ? min(Double(entry.steps) / Double(entry.stepsGoal), 1) : 0
    }
    private var minutesProgress: Double {
        entry.minutesGoal > 0 ? min(Double(entry.minutes) / Double(entry.minutesGoal), 1) : 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline: inlineView
        case .systemSmall: smallView
        default: inlineView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            rings(lineWidth: 5, inset: 7)
            Image(systemName: Self.activityIcon).font(.system(size: 10, weight: .bold))
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            rings(lineWidth: 4, inset: 5).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Label("\(entry.steps.formatted()) / \(entry.stepsGoal.formatted())", systemImage: Self.stepsIcon)
                Label("\(entry.minutes) / \(entry.minutesGoal) min", systemImage: "timer")
                FreshnessStamp(fetchedAt: entry.fetchedAt).foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .semibold))
        }
    }

    private var inlineView: some View {
        Label("\(entry.steps.formatted()) pas · \(entry.minutes) min", systemImage: Self.stepsIcon)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            rings(lineWidth: 9, inset: 11).frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                legendRow(color: Color(red: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255),
                          value: "\(entry.steps.formatted())", unit: "pas")
                legendRow(color: Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255),
                          value: "\(entry.minutes)", unit: "min")
                FreshnessStamp(fetchedAt: entry.fetchedAt).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private func legendRow(color: Color, value: String, unit: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white)
            Text(unit).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func rings(lineWidth: CGFloat, inset: CGFloat) -> some View {
        ZStack {
            arc(stepsProgress, lineWidth: lineWidth, gradient: TodayProgressWidget.stepsGradient)
            arc(minutesProgress, lineWidth: lineWidth, gradient: TodayProgressWidget.minutesGradient)
                .padding(inset)
        }
    }

    private func arc(_ progress: Double, lineWidth: CGFloat, gradient: LinearGradient) -> some View {
        ZStack {
            Circle().stroke(.gray.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress > 0 ? max(progress, 0.03) : 0)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
