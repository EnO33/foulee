import SwiftUI

/// Fitness-style "which days are you most regular" breakdown: one mini bar per
/// weekday (Monday → Sunday) scaled by success rate, with the best active day
/// called out below. Rest days are muted.
struct StreakWeekdayBreakdown: View {
    let stats: [WeekdayStat]

    private let maxBarHeight: CGFloat = 64

    private var best: WeekdayStat? {
        stats.filter { $0.isActive && $0.rate > 0 }.max { $0.rate < $1.rate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(stats) { column($0).frame(maxWidth: .infinity) }
            }
            caption
        }
    }

    private func column(_ stat: WeekdayStat) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.gray.opacity(0.15)).frame(width: 9, height: maxBarHeight)
                Capsule().fill(fill(for: stat)).frame(width: 9, height: barHeight(stat))
            }
            Text(stat.weekday.shortLabel)
                .font(FouleeFont.caption)
                .foregroundStyle(best?.id == stat.id ? FouleeColor.accentMid : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.weekday.fullName)
        .accessibilityValue(stat.isActive ? "\(stat.rate) % de réussite" : "jour de repos")
    }

    private func fill(for stat: WeekdayStat) -> AnyShapeStyle {
        stat.isActive
            ? AnyShapeStyle(FouleeColor.accentGradient)
            : AnyShapeStyle(Color.gray.opacity(0.3))
    }

    private func barHeight(_ stat: WeekdayStat) -> CGFloat {
        guard stat.isActive, stat.rate > 0 else { return 0 }
        return max(maxBarHeight * CGFloat(stat.rate) / 100, 4)
    }

    private var caption: some View {
        Group {
            if let best {
                Text("Tu es le plus régulier le \(best.weekday.fullName) (\(best.rate) %)")
            } else {
                Text("Pas encore assez de données")
            }
        }
        .font(FouleeFont.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
