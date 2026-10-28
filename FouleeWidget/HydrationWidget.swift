import AppIntents
import FouleeKit
import SwiftUI
import WidgetKit

/// Today's water intake vs goal as a single teal ring. The small and
/// rectangular families carry a "+1 verre" button (`LogWaterIntent`) so a
/// glass can be logged without opening the app; the rest of the surface deep
/// links to the home's hydration card (`foulee://hydration`). Reads the shared
/// snapshot (no HealthKit → works on the Lock Screen).
struct HydrationWidget: Widget {
    static let kind = WidgetKind.hydration

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
    let enabled: Bool

    static let placeholder = HydrationEntry(date: .now, waterML: 0, goalML: 2_000, enabled: true)
}

struct HydrationProvider: TimelineProvider {
    func placeholder(in context: Context) -> HydrationEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (HydrationEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HydrationEntry>) -> Void) {
        // Live HealthKit when unlocked, snapshot fallback when locked. Water
        // also pushes instantly via background delivery; this daytime cadence
        // keeps the ring fresh between drinks without burning the budget.
        let box = UncheckedSendableBox(completion)
        Task {
            let snapshot = await WidgetLiveMetrics.freshSnapshot()
            let now = Date.now
            let entry = HydrationEntry(
                date: .now, waterML: snapshot.waterML,
                goalML: snapshot.waterGoalML, enabled: snapshot.hydrationEnabled
            )
            // Pre-rendered zero entry at local midnight — the system swaps to
            // it at 00:00 without a reload, so the ring never shows yesterday.
            let reset = HydrationEntry(
                date: WidgetRefresh.nextMidnight(after: now), waterML: 0,
                goalML: snapshot.waterGoalML, enabled: snapshot.hydrationEnabled
            )
            box.value(Timeline(entries: [entry, reset], policy: .after(WidgetRefresh.nextRefresh(after: now))))
        }
    }

    private func entry() -> HydrationEntry {
        let snapshot = (SharedStore.read() ?? .placeholder).zeroedIfStale()
        return HydrationEntry(
            date: .now, waterML: snapshot.waterML,
            goalML: snapshot.waterGoalML, enabled: snapshot.hydrationEnabled
        )
    }
}

struct HydrationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HydrationEntry

    private var progress: Double {
        entry.goalML > 0 ? min(Double(entry.waterML) / Double(entry.goalML), 1) : 0
    }

    var body: some View {
        if entry.enabled {
            activeView
        } else {
            disabledView
        }
    }

    /// The button families summarise their figures inside, so the button
    /// stays its own element; the others are a single one.
    @ViewBuilder private var activeView: some View {
        switch family {
        case .accessoryRectangular: rectangularView
        case .systemSmall: smallView
        case .accessoryCircular: circularView.widgetSummary(summaryLabel, value: spokenIntake)
        default: inlineView.widgetSummary(summaryLabel, value: spokenIntake)
        }
    }

    private var summaryLabel: Text { Text("Hydratation") }

    /// « 0,9 litre sur 2,0 »: « 0,9 / 2,0 L » reads its slash (issue #601).
    private var spokenIntake: String {
        spokenHydrationText(intakeML: entry.waterML, goalML: entry.goalML)
    }

    /// Shown when the user hasn't turned hydration on: a muted drop inviting
    /// them to enable it, instead of an empty ring that reads as "0 % done".
    @ViewBuilder private var disabledView: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "drop").font(.system(size: 13, weight: .semibold))
            }
        case .accessoryRectangular:
            Label("Hydratation à activer", systemImage: "drop")
                .font(.system(size: 13, weight: .semibold))
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "drop")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Hydratation").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Text("Active-la dans Foulée")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        default:
            Label("Hydratation à activer", systemImage: "drop")
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
            HStack(spacing: 8) {
                ring(lineWidth: 4).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Label("\(litres(entry.waterML)) / \(litres(entry.goalML)) L", systemImage: "drop.fill")
                    Text("\(Int((progress * 100).rounded())) % de l'objectif")
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .widgetSummary(summaryLabel, value: spokenIntake)
            Spacer(minLength: 0)
            rectangularAddButton
        }
    }

    /// Compact "+1 verre" for the Lock Screen: icon over the glass size, so it
    /// stays legible in the tight rectangular slot.
    private var rectangularAddButton: some View {
        addGlassButton { glassML in
            VStack(spacing: 0) {
                Image(systemName: "drop.fill").font(.system(size: 11, weight: .bold))
                Text("+\(glassML)").font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
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
                    .widgetAccentable()
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
        .widgetSummary(summaryLabel, value: spokenIntake)
        .overlay(alignment: .bottomTrailing) { smallAddButton }
        .padding(14)
    }

    private var smallAddButton: some View {
        addGlassButton { glassML in
            Label("+\(glassML) ml", systemImage: "drop.fill")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.white.opacity(0.18), in: Capsule())
        }
    }

    /// The « J'ai bu » button around `label`, which draws the user's glass
    /// size. That size is mirrored into the shared snapshot by the app — the
    /// widget process can't read the app's `UserDefaults.standard` — and read
    /// once for the drawing and VoiceOver: « J'ai bu un verre, 250
    /// millilitres », where the glyph and « +250 » said neither what the
    /// button does nor in what unit (issue #601).
    private func addGlassButton(@ViewBuilder _ label: (Int) -> some View) -> some View {
        let glassML = WaterGlass.milliliters(from: SharedStore.read())
        return Button(intent: LogWaterIntent()) { label(glassML) }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LogWaterIntent.title))
            .accessibilityValue(Text(spokenMillilitresText(glassML)))
    }

    private func ring(lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(.gray.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress > 0 ? max(progress, 0.03) : 0)
                .stroke(HydrationWidget.waterGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // The ring takes the accent colour in the tinted and accented
                // Home Screen modes, where the teal would turn white (#601).
                .widgetAccentable()
        }
    }
}
