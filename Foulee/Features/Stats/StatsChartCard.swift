import Charts
import SwiftUI

/// Bar chart of active minutes per day with a horizontal goal rule.
/// Bars below the goal use a muted gradient so the eye lands on the
/// goal-met days.
struct StatsChartCard: View {
    var data: [DailyMinutes]
    var goalMinutes: Int
    var range: StatsRange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chart
                .frame(height: 220)
            footnote
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 24)
    }

    private var header: some View {
        HStack {
            Text("Minutes par jour")
                .font(FouleeFont.headline)
            Spacer()
            Text(range.label)
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(data) { entry in
                BarMark(
                    x: .value("Jour", entry.date, unit: .day),
                    y: .value("Minutes", entry.minutes)
                )
                .foregroundStyle(entry.minutes >= goalMinutes
                    ? AnyShapeStyle(FouleeColor.accentGradient)
                    : AnyShapeStyle(Color.gray.opacity(0.25)))
                .cornerRadius(4)
            }
            if goalMinutes > 0 {
                RuleMark(y: .value("Objectif", goalMinutes))
                    .foregroundStyle(FouleeColor.success.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Objectif \(goalMinutes) min")
                            .font(FouleeFont.caption.weight(.semibold))
                            .foregroundStyle(FouleeColor.success)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range.axisCount)) { value in
                AxisGridLine()
                AxisValueLabel(format: range.dateFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private var footnote: some View {
        Text("Source : Santé (minutes d'exercice).")
            .font(FouleeFont.caption)
            .foregroundStyle(.secondary)
    }
}

extension StatsRange {
    var axisCount: Int {
        switch self {
        case .week: 7
        case .month: 6
        case .year: 6
        }
    }

    var dateFormat: Date.FormatStyle {
        switch self {
        case .week: .dateTime.weekday(.narrow)
        case .month: .dateTime.day().month(.narrow)
        case .year: .dateTime.month(.abbreviated)
        }
    }
}
