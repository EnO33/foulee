import Dependencies
import SwiftUI

/// Glass card holding the day's or the week's 4 stat blocks (pas / minutes /
/// distance / calories). Each block is a button that opens the metric's stats.
///
/// **Two tabs, one card** (issue #327). « Semaine » took the place of the
/// separate « Cette semaine » card: the same four tiles summed from Monday.
/// The day by day lives in the Bilan (#350), not under them. And the tabs are « Jour » / « Semaine » rather than
/// « Aujourd'hui », which the screen's own title already says.
struct TodayStatsGrid: View {
    enum Period: Hashable {
        case day
        case week
    }

    var snapshot: TodaySnapshot
    var onSelectMetric: (WalkMetric) -> Void

    @Dependency(\.healthKit) private var healthKit
    @State private var period: Period = .day
    /// Pas, distance and calories since Monday; `nil` until read.
    @State private var weekTotals: WeekTotals?

    private static let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Période", selection: $period) {
                Text("Jour").tag(Period.day)
                Text("Semaine").tag(Period.week)
            }
            .pickerStyle(.segmented)
            LazyVGrid(columns: Self.columns, spacing: 18) {
                tiles
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 24)
        // Only while « Semaine » is shown, and again whenever the day's
        // figures move: today is part of the week, so a step taken now has to
        // reach its total too. Nothing is read for a tab nobody opened.
        .task(id: period == .week ? snapshot : nil) {
            guard period == .week else { return }
            weekTotals = await loadWeekTotals()
        }
    }

    @ViewBuilder
    private var tiles: some View {
        switch period {
        case .day:
            stepsTile(snapshot.steps.formattedFR, sub: "/ \(snapshot.stepsGoal.formattedFR)")
            minutesTile("\(snapshot.minutes)", sub: "/ \(snapshot.minutesGoal)")
            distanceTile(snapshot.distanceKm.kmText(fractionDigits: 1))
            caloriesTile(snapshot.calories.formattedFR)
        case .week:
            // Minutes are known at once — the snapshot already holds the
            // week's. The three others wait for HealthKit, and say « — »
            // rather than a zero that would read as a real total.
            stepsTile(weekTotals.map { $0.steps.formattedFR } ?? "—", sub: nil)
            minutesTile("\(snapshot.weekMinutes.reduce(0, +))", sub: "min")
            distanceTile(weekTotals.map { $0.distanceKm.kmText(fractionDigits: 1) } ?? "—")
            caloriesTile(weekTotals.map { $0.calories.formattedFR } ?? "—")
        }
    }

    private func stepsTile(_ value: String, sub: String?) -> some View {
        metricButton(.steps) {
            StatBlock(systemIcon: FouleeIcon.footsteps, label: "Pas", value: value, sub: sub, tint: FouleeColor.accentMid)
        }
    }

    private func minutesTile(_ value: String, sub: String) -> some View {
        metricButton(.minutes) {
            StatBlock(
                systemIcon: FouleeIcon.timer,
                label: "Minutes",
                value: value,
                sub: sub,
                tint: FouleeColor.accentSecondary
            )
        }
    }

    private func distanceTile(_ value: String) -> some View {
        metricButton(.distance) {
            StatBlock(systemIcon: FouleeIcon.distance, label: "Distance", value: value, sub: nil, tint: Color(hex: 0x0A84FF))
        }
    }

    private func caloriesTile(_ value: String) -> some View {
        metricButton(.calories) {
            StatBlock(systemIcon: FouleeIcon.flame, label: "Calories", value: value, sub: "kcal", tint: FouleeColor.warning)
        }
    }

    /// The three daily series from Monday on, read together. A failed read
    /// leaves the tiles on « — » rather than inventing a total.
    private func loadWeekTotals() async -> WeekTotals? {
        let today = snapshot.date
        let days = WeekTotals.daysSoFar(at: today)
        async let steps = healthKit.metricSeries(.steps, days)
        async let distance = healthKit.metricSeries(.distance, days)
        async let calories = healthKit.metricSeries(.calories, days)
        guard let steps = try? await steps,
              let distance = try? await distance,
              let calories = try? await calories
        else { return nil }
        return WeekTotals(
            steps: Int(WeekTotals.sum(steps, weekOf: today)),
            distanceKm: WeekTotals.sum(distance, weekOf: today),
            calories: Int(WeekTotals.sum(calories, weekOf: today))
        )
    }

    private func metricButton<Content: View>(
        _ metric: WalkMetric,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button { onSelectMetric(metric) } label: {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Voir les statistiques")
        .accessibilityIdentifier(TodayAccessibility.metricCard(metric))
    }
}
