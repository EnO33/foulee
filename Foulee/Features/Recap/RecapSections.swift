import SwiftUI

/// The top of a recap (issue #346): the goal ring, the minutes, and one
/// sentence that says what the period meant — before any detail.
struct RecapHero: View {
    let recap: Recap
    var isRevealed = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The ring above the text at the accessibility sizes (#371), beside it
    /// otherwise.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
    }

    var body: some View {
        layout {
            ProgressRing(
                progress: isRevealed ? recap.goalRate : 0,
                lineWidth: 14,
                gradient: FouleeColor.activityGradient,
                trackColor: Color.gray.opacity(0.18)
            ) {
                VStack(spacing: 0) {
                    Text(recap.goalDaysPlanned > 0 ? "\(recap.goalDaysMet)/\(recap.goalDaysPlanned)" : "–")
                        .scaledNumericFont(size: 22)
                    Text("objectifs")
                        .font(FouleeFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Objectif tenu \(recap.goalDaysMet) jours sur \(recap.goalDaysPlanned)")

            VStack(alignment: .leading, spacing: 6) {
                Text(recap.period.title)
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(durationText(minutes: isRevealed ? recap.totals.minutes : 0))
                        .scaledNumericFont(size: 34)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    RecapChangeChip(old: Double(recap.previous.minutes), new: Double(recap.totals.minutes))
                }
                Text(verdictText)
                    .font(FouleeFont.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FouleeColor.activityGradient)
                .opacity(0.12)
        }
        .fouleeGlass(cornerRadius: 24, strong: true)
    }

    private var isWeek: Bool { recap.period.kind == .week }

    private var verdictText: String {
        switch recap.verdict {
        case .quiet: "Une période au calme. La prochaine sera la bonne !"
        case .perfect: isWeek ? "Semaine parfaite : objectif tenu chaque jour prévu." : "Mois parfait : objectif tenu chaque jour prévu."
        case .steady: "Belle régularité, continue comme ça."
        case .improving: "En progrès par rapport à la période d'avant."
        case .started: "Chaque sortie compte : vise un jour de plus la prochaine fois."
        }
    }
}

/// This period against the one before (issue #346), one measure per row: two
/// bars on a shared scale — this period in the measure's colour, the one
/// before in grey — and the change.
struct RecapComparison: View {
    let recap: Recap
    var isRevealed = true

    private struct Row: Identifiable {
        var label: String
        var icon: String
        var tint: AnyShapeStyle
        var now: Double
        var before: Double
        var text: (Double) -> String

        var id: String { label }
    }

    private var rows: [Row] {
        let now = recap.totals
        let before = recap.previous
        return [
            Row(label: "Minutes", icon: FouleeIcon.timer, tint: AnyShapeStyle(FouleeColor.activityGradient),
                now: Double(now.minutes), before: Double(before.minutes)) { durationText(minutes: Int($0)) },
            Row(label: "Pas", icon: FouleeIcon.footsteps, tint: AnyShapeStyle(FouleeColor.accentGradient),
                now: Double(now.steps), before: Double(before.steps)) { Int($0).formattedFR },
            Row(label: "Distance", icon: FouleeIcon.distance, tint: AnyShapeStyle(WalkMetric.distance.tint),
                now: now.distanceKm, before: before.distanceKm) { $0.kmText(fractionDigits: 1) },
            Row(label: "Sorties", icon: "figure.walk", tint: AnyShapeStyle(FouleeColor.accentMid),
                now: Double(now.outings), before: Double(before.outings)) { "\(Int($0))" }
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: row.icon)
                            .foregroundStyle(row.tint)
                        Text(row.label)
                            .font(FouleeFont.footnote.weight(.semibold))
                        Spacer()
                        Text(row.text(row.now))
                            .font(FouleeFont.callout.weight(.bold).monospacedDigit())
                        RecapChangeChip(old: row.before, new: row.now)
                    }
                    bar(row.now, of: row, style: row.tint)
                    bar(row.before, of: row, style: AnyShapeStyle(Color.gray.opacity(0.35)))
                    Text("Avant : \(row.text(row.before))")
                        .font(FouleeFont.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label) : \(row.text(row.now)), contre \(row.text(row.before)) avant")
            }
        }
    }

    /// A bar on the row's shared scale: the larger of the two values fills it.
    private func bar(_ value: Double, of row: Row, style: AnyShapeStyle) -> some View {
        let scale = max(row.now, row.before)
        let fraction = scale > 0 && isRevealed ? value / scale : 0
        return GeometryReader { geo in
            Capsule()
                .fill(style)
                .frame(width: max(fraction * geo.size.width, value > 0 && isRevealed ? 6 : 0))
        }
        .frame(height: 8)
    }
}

/// The period's high points (issue #346): its best day, and the energy spent.
struct RecapHighlights: View {
    let recap: Recap

    var body: some View {
        HStack(spacing: 12) {
            if let best = recap.bestDay {
                tile(
                    icon: "trophy.fill",
                    tint: FouleeColor.warning,
                    title: "Meilleur jour",
                    value: durationText(minutes: best.minutes),
                    detail: Self.dayFormatter.string(from: best.date).capitalized(with: Locale(identifier: "fr_FR"))
                )
            }
            tile(
                icon: FouleeIcon.flame,
                tint: FouleeColor.danger,
                title: "Énergie",
                value: "\(recap.totals.calories.formattedFR) kcal",
                detail: "\(recap.totals.outings) sortie\(recap.totals.outings > 1 ? "s" : "")"
            )
        }
    }

    private func tile(icon: String, tint: Color, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .scaledNumericFont(size: 22)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .fouleeGlass(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMM"
        return formatter
    }()
}

/// The period's water (issue #356): the daily mean against the period before,
/// and the days the goal held, in the colour of water.
struct RecapHydration: View {
    let water: RecapWater
    var isRevealed = true

    private var goalText: String {
        let days = "\(water.goalDaysMet) jour\(water.goalDaysMet > 1 ? "s" : "")"
        return "Objectif de \(litres(water.goalML)) L tenu \(days) sur \(water.dayCount)"
    }

    private var goalRate: Double {
        water.dayCount > 0 ? Double(water.goalDaysMet) / Double(water.dayCount) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(HydrationCard.water)
                Text("\(litres(water.averageML)) L")
                    .scaledNumericFont(size: 26)
                Text("par jour en moyenne")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                RecapChangeChip(old: Double(water.previousAverageML), new: Double(water.averageML))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.18))
                    Capsule()
                        .fill(HydrationCard.water.gradient)
                        .frame(width: geo.size.width * (isRevealed ? goalRate : 0))
                }
            }
            .frame(height: 8)
            Text(goalText)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hydratation")
        .accessibilityValue(
            "\(litres(water.averageML)) litre par jour en moyenne, objectif tenu \(water.goalDaysMet) jours sur \(water.dayCount)"
        )
    }
}
