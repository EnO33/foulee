import FouleeKit
import SwiftUI

/// The streak at the head of the Bilan (issue #445): the flame, the days in a
/// row, and how far the record is.
struct RecapStreakHeader: View {
    let streak: StreakSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The flame above the text at the accessibility sizes: beside it,
            // « SÉRIE ACTUELLE » broke mid-word (issue #658).
            AdaptiveStack(stacked: VStackLayout(alignment: .leading, spacing: 14), regular: HStackLayout(spacing: 14)) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FouleeColor.streakGradient)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: FouleeIcon.flame)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Color(hex: 0xFF6B00).opacity(0.35), radius: 14, y: 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SÉRIE ACTUELLE")
                        .font(FouleeFont.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak.current)")
                            .scaledNumericFont(size: 36)
                        Text(streak.current == 1 ? "jour" : "jours")
                            .font(FouleeFont.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(recordTitle)
                        .font(FouleeFont.headline)
                    Spacer()
                    if streak.best > 0 {
                        Text("\(streak.current) / \(streak.best)")
                            .scaledNumericFont(size: 15, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Record : \(streak.best) jours"))
                    }
                }
                RecordBar(progress: streak.recordProgress)
                    .frame(height: 8)
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    private var recordTitle: LocalizedStringResource {
        if streak.best == 0 { return "Lance ta première série 🔥" }
        guard let remaining = streak.daysToRecord else { return "🔥 Nouveau record !" }
        return "Plus que \(remaining) jours pour ton record"
    }
}

/// The year at the foot of the Bilan (issue #445): its totals, and the
/// weekdays kept best. The same whatever the period on screen.
struct RecapYear: View {
    let streak: StreakSummary

    var body: some View {
        GlassSection("Sur 12 mois") {
            FigureRow {
                total(value: "\(streak.walks)", label: streak.walks == 1 ? "objectif tenu" : "objectifs tenus")
                total(value: durationText(minutes: streak.minutes), label: "d'activité")
                total(value: "\(streak.rate) %", label: "réussite")
            }
        }
        GlassSection("Tes jours les plus réguliers") {
            StreakWeekdayBreakdown(stats: streak.weekdays)
        }
    }

    private func total(value: String, label: LocalizedStringResource) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .scaledNumericFont(size: 20, weight: .semibold)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// Track and fill toward the record.
private struct RecordBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.16))
                Capsule()
                    .fill(FouleeColor.streakGradient)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .accessibilityHidden(true)
    }
}
