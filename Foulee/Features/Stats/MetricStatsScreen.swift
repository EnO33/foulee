import Charts
import Dependencies
import SwiftUI

/// Per-metric stats, opened by tapping a card on the Today screen. A segmented
/// control switches the chart between Aujourd'hui (hourly curve), Semaine and
/// Mois (daily bars). Presented as a sheet.
struct MetricStatsScreen: View {
    let metric: WalkMetric
    /// Daily goal for steps/minutes (draws a reference line); nil otherwise.
    var dailyGoal: Double?
    var onClose: () -> Void

    @State private var store: MetricStatsStore

    init(metric: WalkMetric, dailyGoal: Double?, onClose: @escaping () -> Void) {
        self.metric = metric
        self.dailyGoal = dailyGoal
        self.onClose = onClose
        _store = State(initialValue: MetricStatsStore(metric: metric))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SheetBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    rangePicker
                    chartCard
                    if !store.isEmpty {
                        summaryCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            closeButton
                .padding(20)
        }
        .task(id: store.range) { await store.load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: metric.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(metric.tint)
                .frame(width: 46, height: 46)
                .background(metric.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("STATISTIQUES")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.1)
                Text(metric.title)
                    .font(FouleeFont.largeTitle)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 48) // clear of the close button
    }

    private var rangePicker: some View {
        Picker("Période", selection: $store.range) {
            ForEach(MetricRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chartTitle)
                .font(FouleeFont.headline)
            if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if store.isEmpty {
                emptyChart
            } else {
                chart.frame(height: 200)
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 24)
    }

    private var chart: some View {
        Chart {
            ForEach(store.points) { point in
                BarMark(
                    x: .value("Temps", point.date, unit: store.range == .today ? .hour : .day),
                    y: .value(metric.title, point.value)
                )
                .foregroundStyle(barStyle(for: point.value))
                .cornerRadius(3)
            }
            if let dailyGoal, store.range != .today {
                RuleMark(y: .value("Objectif", dailyGoal))
                    .foregroundStyle(FouleeColor.success.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Objectif \(metric.formattedWithUnit(dailyGoal))")
                            .font(FouleeFont.caption.weight(.semibold))
                            .foregroundStyle(FouleeColor.success)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: xAxisFormat)
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
    }

    private func barStyle(for value: Double) -> AnyShapeStyle {
        // Below-goal daily bars are muted so goal-met days stand out; the
        // hourly view and goal-less metrics use the metric's tint throughout.
        if let dailyGoal, store.range != .today, value < dailyGoal {
            return AnyShapeStyle(Color.gray.opacity(0.25))
        }
        return AnyShapeStyle(metric.tint.gradient)
    }

    private var xAxisFormat: Date.FormatStyle {
        switch store.range {
        case .today: .dateTime.hour()
        case .week: .dateTime.weekday(.narrow)
        case .month: .dateTime.day().month(.narrow)
        case .year: .dateTime.month(.narrow)
        }
    }

    private var chartTitle: String {
        switch store.range {
        case .today: "\(metric.title) par heure"
        case .week, .month, .year: "\(metric.title) par jour"
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            ForEach(Array(summaryItems.enumerated()), id: \.offset) { index, item in
                if index > 0 { divider }
                summaryCell(label: item.label, value: item.value)
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    private var summaryItems: [(label: String, value: String)] {
        switch store.range {
        case .today:
            [("Total", metric.formattedWithUnit(store.total)),
             ("Meilleure heure", metric.formattedWithUnit(store.best))]
        case .week, .month, .year:
            [("Total", metric.formattedWithUnit(store.total)),
             ("Moyenne / jour", metric.formattedWithUnit(store.average)),
             ("Meilleur jour", metric.formattedWithUnit(store.best))]
        }
    }

    private func summaryCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(FouleeFont.numeric(size: 20, weight: .semibold))
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

    private var divider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.25))
            .frame(width: 1, height: 34)
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: metric.icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Aucune donnée sur cette période")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Fermer")
    }
}

private extension WalkMetric {
    var icon: String {
        switch self {
        case .steps: FouleeIcon.footsteps
        case .minutes: FouleeIcon.timer
        case .distance: FouleeIcon.distance
        case .calories: FouleeIcon.flame
        }
    }

    var tint: Color {
        switch self {
        case .steps: FouleeColor.accentMid
        case .minutes: FouleeColor.accentSecondary
        case .distance: Color(hex: 0x0A84FF)
        case .calories: FouleeColor.warning
        }
    }
}

private struct MetricStatsPreview: View {
    init() { prepareDependencies { $0.healthKit = .previewValue } }
    var body: some View {
        MetricStatsScreen(metric: .steps, dailyGoal: 6_000, onClose: {})
    }
}

#Preview { MetricStatsPreview() }
