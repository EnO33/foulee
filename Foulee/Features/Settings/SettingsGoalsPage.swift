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
            SettingsSlider(
                title: "Objectif d'activité",
                value: $preferences.minutesGoal,
                range: 10...60,
                step: 5,
                tint: FouleeColor.accentMid
            ) { "\($0) min" }
        }
        // Tracked all day — a session only contributes to it — so it stands
        // apart from the activity goal.
        GlassSection("Objectif de pas", footer: "Compté toute la journée, ta sortie incluse.") {
            SettingsSlider(
                title: "Objectif de pas",
                value: $preferences.stepsGoal,
                range: 2_000...15_000,
                step: 500,
                tint: FouleeColor.accentMid
            ) { "\($0.formattedFR) pas" }
        }
    }
}
