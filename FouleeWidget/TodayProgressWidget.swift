import SwiftUI
import WidgetKit

/// Today's two daily goals at a glance — steps and activity minutes — as a
/// double progress ring. On the Lock Screen (accessory families) the system
/// renders it monochrome, so the two goals read as two concentric arcs; on the
/// Home Screen they keep their colours (purple steps, green activity).
struct TodayProgressWidget: Widget {
    static let kind = "com.eno33.foulee.todayWidget"

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

    static let placeholder = TodayEntry(date: .now, steps: 0, stepsGoal: 6_000, minutes: 0, minutesGoal: 20)
}

/// Reads today's progress from the snapshot the app writes to the app group
/// (no HealthKit in the widget, so it still works while the phone is locked).
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date(timeIntervalSinceNow: 30 * 60))))
    }

    private func entry() -> TodayEntry {
        let snapshot = SharedStore.read() ?? .placeholder
        return TodayEntry(
            date: .now,
            steps: snapshot.steps,
            stepsGoal: snapshot.stepsGoal,
            minutes: snapshot.minutes,
            minutesGoal: snapshot.minutesGoal
        )
    }
}

struct TodayProgressView: View {
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
            Image(systemName: "figure.walk").font(.system(size: 10, weight: .bold))
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            rings(lineWidth: 4, inset: 5).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Label("\(entry.steps.formatted()) / \(entry.stepsGoal.formatted())", systemImage: "figure.walk")
                Label("\(entry.minutes) / \(entry.minutesGoal) min", systemImage: "timer")
            }
            .font(.system(size: 12, weight: .semibold))
        }
    }

    private var inlineView: some View {
        Label("\(entry.steps.formatted()) pas · \(entry.minutes) min", systemImage: "figure.walk")
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            rings(lineWidth: 9, inset: 11).frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                legendRow(color: Color(red: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255),
                          value: "\(entry.steps.formatted())", unit: "pas")
                legendRow(color: Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255),
                          value: "\(entry.minutes)", unit: "min")
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
