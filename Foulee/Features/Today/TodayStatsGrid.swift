import SwiftUI

/// Glass card holding the 4 daily stat blocks (pas / minutes / distance /
/// calories).
struct TodayStatsGrid: View {
    var snapshot: TodaySnapshot

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
                StatBlock(
                    systemIcon: FouleeIcon.footsteps,
                    label: "Pas",
                    value: snapshot.steps.formattedFR,
                    sub: "/ \(snapshot.stepsGoal.formattedFR)",
                    tint: FouleeColor.accentMid
                )
                StatBlock(
                    systemIcon: FouleeIcon.timer,
                    label: "Minutes",
                    value: "\(snapshot.minutes)",
                    sub: "/ \(snapshot.minutesGoal)",
                    tint: FouleeColor.accentSecondary
                )
                StatBlock(
                    systemIcon: FouleeIcon.distance,
                    label: "Distance",
                    value: snapshot.distanceKm.kmText(fractionDigits: 1),
                    sub: nil,
                    tint: Color(hex: 0x0A84FF)
                )
                StatBlock(
                    systemIcon: FouleeIcon.flame,
                    label: "Calories",
                    value: "\(snapshot.calories)",
                    sub: "kcal",
                    tint: FouleeColor.warning
                )
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 24)
    }
}
