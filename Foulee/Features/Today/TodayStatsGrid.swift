import Dependencies
import FouleeKit
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Période", selection: $period) {
                Text("Jour").tag(Period.day)
                Text("Semaine").tag(Period.week)
            }
            .pickerStyle(.segmented)
            AdaptiveGrid(columns: 2, accessibilityColumns: 1, spacing: 18) {
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
            tile(
                .steps,
                snapshot.steps.groupedText(),
                sub: "/ \(snapshot.stepsGoal.groupedText())",
                spoken: String(localized: "\(snapshot.steps.groupedText()) sur \(snapshot.stepsGoal.groupedText())")
            )
            tile(
                .minutes,
                "\(snapshot.minutes)",
                sub: "/ \(snapshot.minutesGoal)",
                spoken: String(localized: "\(snapshot.minutes) minutes sur \(snapshot.minutesGoal)")
            )
            tile(.distance, snapshot.distanceKm.kmText(fractionDigits: 1))
            tile(.calories, snapshot.calories.groupedText(), sub: "kcal")
        case .week:
            // Minutes are known at once — the snapshot already holds the
            // week's — and read as a duration, « 6 h » rather than
            // « 360 min » (#366). The three others wait for HealthKit, and say
            // « — » rather than a zero that would read as a real total.
            tile(.steps, weekTotals.map { $0.steps.groupedText() } ?? "—")
            let weekMinutes = snapshot.weekMinutes.reduce(0, +)
            tile(.minutes, durationText(minutes: weekMinutes), spoken: spokenDurationText(minutes: weekMinutes))
            tile(.distance, weekTotals.map { $0.distanceKm.kmText(fractionDigits: 1) } ?? "—")
            tile(.calories, weekTotals.map { $0.calories.groupedText() } ?? "—", sub: "kcal")
        }
    }

    /// A metric's tile, in its ring's colour (#366).
    private func tile(_ metric: WalkMetric, _ value: String, sub: String? = nil, spoken: String? = nil) -> some View {
        metricButton(metric) {
            StatBlock(
                systemIcon: metric.icon,
                label: .verbatim(metric.title),
                value: value,
                sub: sub,
                spokenValue: spoken,
                tint: metric.tint
            )
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
