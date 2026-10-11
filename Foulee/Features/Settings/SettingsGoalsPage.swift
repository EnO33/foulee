import SwiftUI

/// Objectifs: what the user moves at, and how much a day.
struct SettingsGoalsPage: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        GlassSection("Activité", footer: "Ta série compte toutes tes activités, quel que soit ce choix.") {
            // Segmented: three short labels, one tap. The footnote is the
            // literal truth rather than reassurance — the streak, the record
            // and the calendar count exercise minutes across every activity
            // type and never read this preference (#220).
            Picker("Activité", selection: $preferences.activityMode) {
                ForEach(ActivityMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        // The session duration that drives the ring and the « démarrer ta
        // sortie » flow.
        GlassSection("Objectif d'activité") {
            goalSlider(
                value: "\(preferences.minutesGoal) min",
                binding: Binding(
                    get: { Double(preferences.minutesGoal) },
                    set: { preferences.minutesGoal = Int($0) }
                ),
                range: 10...60,
                step: 5
            )
        }
        // Tracked all day — a session only contributes to it — so it stands
        // apart from the activity goal.
        GlassSection("Objectif de pas", footer: "Compté toute la journée, ta sortie incluse.") {
            goalSlider(
                value: "\(preferences.stepsGoal.formattedFR) pas",
                binding: Binding(
                    get: { Double(preferences.stepsGoal) },
                    set: { preferences.stepsGoal = Int($0) }
                ),
                range: 2_000...15_000,
                step: 500
            )
        }
    }

    private func goalSlider(
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value)
                .scaledNumericFont(size: 20, weight: .semibold)
                .foregroundStyle(FouleeColor.accentMid)
            Slider(value: binding, in: range, step: step)
                .tint(FouleeColor.accentMid)
        }
    }
}
