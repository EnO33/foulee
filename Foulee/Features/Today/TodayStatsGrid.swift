import SwiftUI

/// Glass card holding the 4 daily stat blocks (pas / minutes / distance /
/// calories). Each block is a button that opens the metric's stats.
struct TodayStatsGrid: View {
    var snapshot: TodaySnapshot
    var onSelectMetric: (WalkMetric) -> Void

    private static let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Aujourd'hui")
                    .font(FouleeFont.headline)
                Spacer()
                Text("Mis à jour : maintenant")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Self.columns, spacing: 18) {
                metricButton(.steps) {
                    StatBlock(
                        systemIcon: FouleeIcon.footsteps,
                        label: "Pas",
                        value: snapshot.steps.formattedFR,
                        sub: "/ \(snapshot.stepsGoal.formattedFR)",
                        tint: FouleeColor.accentMid
                    )
                }
                metricButton(.minutes) {
                    StatBlock(
                        systemIcon: FouleeIcon.timer,
                        label: "Minutes",
                        value: "\(snapshot.minutes)",
                        sub: "/ \(snapshot.minutesGoal)",
                        tint: FouleeColor.accentSecondary
                    )
                }
                metricButton(.distance) {
                    StatBlock(
                        systemIcon: FouleeIcon.distance,
                        label: "Distance",
                        value: snapshot.distanceKm.kmText(fractionDigits: 1),
                        sub: nil,
                        tint: Color(hex: 0x0A84FF)
                    )
                }
                metricButton(.calories) {
                    StatBlock(
                        systemIcon: FouleeIcon.flame,
                        label: "Calories",
                        value: "\(snapshot.calories)",
                        sub: "kcal",
                        tint: FouleeColor.warning
                    )
                }
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 24)
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
