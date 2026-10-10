import Charts
import SwiftUI

/// The week or the month in review (issue #344): what was done, against the
/// goal and against the period before.
struct RecapScreen: View {
    let goalMinutes: Int
    let activeDays: Set<Weekday>
    var onClose: () -> Void

    @State private var kind: RecapPeriod.Kind
    @State private var store = RecapStore()

    init(kind: RecapPeriod.Kind, goalMinutes: Int, activeDays: Set<Weekday>, onClose: @escaping () -> Void) {
        _kind = State(initialValue: kind)
        self.goalMinutes = goalMinutes
        self.activeDays = activeDays
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("Période", selection: $kind) {
                    ForEach(RecapPeriod.Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if let recap = store.recaps[kind] {
                    RecapContent(recap: recap)
                } else if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if store.lastError != nil {
                    Text("Impossible de lire tes données Santé pour le moment.")
                        .font(FouleeFont.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.pressable)
            .padding(20)
            .accessibilityLabel("Fermer")
        }
        .presentationBackground { SheetBackground() }
        .task { await store.load(goalMinutes: goalMinutes, activeDays: activeDays) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RÉCAP")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text("Ton bilan")
                .font(FouleeFont.largeTitle)
        }
    }
}

/// One recap, laid out: the minutes and the goal first — what the app is
/// about — then the day by day, then the other counters.
private struct RecapContent: View {
    let recap: Recap

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(recap.period.title)
                .font(FouleeFont.title3)
            if recap.isEmpty {
                Text("Aucune activité enregistrée sur cette période. La prochaine sera la bonne !")
                    .font(FouleeFont.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .fouleeGlass(cornerRadius: 22)
            } else {
                hero
                RecapDaysChart(recap: recap)
                    .padding(16)
                    .fouleeGlass(cornerRadius: 22)
                counters
                if let best = recap.bestDay {
                    Label("Meilleur jour : \(Self.dayFormatter.string(from: best.date)) · \(best.minutes) min", systemImage: "trophy.fill")
                        .font(FouleeFont.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var comparison: String {
        recap.period.kind == .week ? "vs semaine précédente" : "vs mois précédent"
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(recap.totals.minutes)")
                    .scaledNumericFont(size: 44)
                Text("min d'activité")
                    .font(FouleeFont.callout)
                    .foregroundStyle(.secondary)
            }
            RecapChangeText(old: Double(recap.previous.minutes), new: Double(recap.totals.minutes), suffix: comparison)
            if recap.goalDaysPlanned > 0 {
                Label(
                    "Objectif de \(recap.goalMinutes) min tenu \(recap.goalDaysMet) jour\(recap.goalDaysMet > 1 ? "s" : "") "
                        + "sur \(recap.goalDaysPlanned)",
                    systemImage: FouleeIcon.target
                )
                .font(FouleeFont.callout.weight(.semibold))
                .foregroundStyle(recap.goalDaysMet == recap.goalDaysPlanned ? FouleeColor.success : FouleeColor.accentMid)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .fouleeGlass(cornerRadius: 22)
    }

    /// One counter of the grid, with the same counter for the period before.
    private struct Counter {
        var label: String
        var icon: String
        var value: String
        var unit: String?
        var tint: Color
        var old: Double
        var new: Double
    }

    private var countersData: [Counter] {
        let now = recap.totals
        let before = recap.previous
        return [
            Counter(label: "Pas", icon: FouleeIcon.footsteps, value: now.steps.formattedFR, tint: FouleeColor.accentMid,
                    old: Double(before.steps), new: Double(now.steps)),
            Counter(label: "Distance", icon: FouleeIcon.distance, value: now.distanceKm.kmText(fractionDigits: 1),
                    tint: FouleeColor.accentSecondary, old: before.distanceKm, new: now.distanceKm),
            Counter(label: "Calories", icon: FouleeIcon.flame, value: "\(now.calories)", unit: "kcal", tint: FouleeColor.warning,
                    old: Double(before.calories), new: Double(now.calories)),
            Counter(label: "Sorties", icon: "figure.walk", value: "\(now.outings)", tint: FouleeColor.success,
                    old: Double(before.outings), new: Double(now.outings))
        ]
    }

    private var counters: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(countersData, id: \.label) { counter in
                VStack(alignment: .leading, spacing: 6) {
                    StatBlock(systemIcon: counter.icon, label: counter.label, value: counter.value, sub: counter.unit, tint: counter.tint)
                    RecapChangeText(old: counter.old, new: counter.new, suffix: nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .fouleeGlass(cornerRadius: 20)
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMM"
        return formatter
    }()
}

/// « +12 % vs semaine précédente » — or nothing, when there was nothing to
/// compare with.
private struct RecapChangeText: View {
    let old: Double
    let new: Double
    let suffix: String?

    var body: some View {
        if let change = Recap.change(from: old, to: new) {
            let percent = Int((change * 100).rounded())
            Text([percent == 0 ? "=" : "\(percent > 0 ? "+" : "−")\(abs(percent)) %", suffix].compactMap { $0 }.joined(separator: " "))
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(percent >= 0 ? FouleeColor.success : Color.secondary)
        }
    }
}

/// Minutes day by day, the goal as a line: a day that reached it stands out
/// in the accent gradient.
private struct RecapDaysChart: View {
    let recap: Recap

    var body: some View {
        Chart {
            ForEach(recap.days) { day in
                BarMark(
                    x: .value("Jour", day.date, unit: .day),
                    y: .value("Minutes", day.minutes)
                )
                .foregroundStyle(day.minutes >= recap.goalMinutes
                    ? AnyShapeStyle(FouleeColor.accentGradient)
                    : AnyShapeStyle(FouleeColor.accentMid.opacity(0.35)))
                .cornerRadius(3)
            }
            RuleMark(y: .value("Objectif", recap.goalMinutes))
                .foregroundStyle(FouleeColor.success)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .chartXAxis {
            if recap.period.kind == .week {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day())
                }
            }
        }
        .environment(\.locale, Locale(identifier: "fr_FR"))
        .frame(height: 160)
        .accessibilityLabel("Minutes d'activité par jour")
    }
}
