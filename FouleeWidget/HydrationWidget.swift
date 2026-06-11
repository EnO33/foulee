import SwiftUI
import WidgetKit

/// Today's water intake vs goal as a single teal ring. Tapping the widget deep
/// links to the home's hydration card (`foulee://hydration`) where "J'ai bu"
/// lives. Reads the shared snapshot (no HealthKit → works on the Lock Screen).
struct HydrationWidget: Widget {
    static let kind = "com.eno33.foulee.hydrationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HydrationProvider()) { entry in
            HydrationWidgetView(entry: entry)
                .containerBackground(TodayProgressWidget.containerBackground, for: .widget)
                .widgetURL(URL(string: "foulee://hydration"))
        }
        .configurationDisplayName("Hydratation")
        .description("Ton eau bue du jour, par rapport à ton objectif.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }

    static let waterGradient = LinearGradient(
        colors: [Color(red: 0x5A / 255, green: 0xC8 / 255, blue: 0xFA / 255),
                 Color(red: 0x32 / 255, green: 0xAD / 255, blue: 0xE6 / 255),
                 Color(red: 0x00 / 255, green: 0x78 / 255, blue: 0xA8 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct HydrationEntry: TimelineEntry, Sendable {
    let date: Date
    let waterML: Int
    let goalML: Int

    static let placeholder = HydrationEntry(date: .now, waterML: 0, goalML: 2_000)
}

struct HydrationProvider: TimelineProvider {
    func placeholder(in context: Context) -> HydrationEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (HydrationEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HydrationEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date(timeIntervalSinceNow: 30 * 60))))
    }

    private func entry() -> HydrationEntry {
        let snapshot = SharedStore.read() ?? .placeholder
        return HydrationEntry(date: .now, waterML: snapshot.waterML, goalML: snapshot.waterGoalML)
    }
}

struct HydrationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HydrationEntry

    private var progress: Double {
        entry.goalML > 0 ? min(Double(entry.waterML) / Double(entry.goalML), 1) : 0
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
            ring(lineWidth: 5)
                .padding(3)
            Image(systemName: "drop.fill").font(.system(size: 11, weight: .bold))
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            ring(lineWidth: 4).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Label("\(litres(entry.waterML)) / \(litres(entry.goalML)) L", systemImage: "drop.fill")
                Text("\(Int((progress * 100).rounded())) % de l'objectif")
            }
            .font(.system(size: 12, weight: .semibold))
        }
    }

    private var inlineView: some View {
        Label("\(litres(entry.waterML)) / \(litres(entry.goalML)) L", systemImage: "drop.fill")
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                ring(lineWidth: 9)
                Image(systemName: "drop.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0x5A / 255, green: 0xC8 / 255, blue: 0xFA / 255))
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(litres(entry.waterML)) L")
                    .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white)
                Text("sur \(litres(entry.goalML)) L")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private func ring(lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(.gray.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress > 0 ? max(progress, 0.03) : 0)
                .stroke(HydrationWidget.waterGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    /// Millilitres → "1,5" (one decimal, comma separator).
    private func litres(_ millilitres: Int) -> String {
        String(format: "%.1f", Double(millilitres) / 1_000)
            .replacingOccurrences(of: ".", with: ",")
    }
}
