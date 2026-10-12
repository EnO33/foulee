import FouleeKit
import SwiftUI

/// The Hydratation settings page — the on/off toggle and, when on, the daily
/// goal, the glass size and the reminders.
struct HydrationSettingsContent: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle(isOn: $preferences.hydrationEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suivi d'hydratation")
                        .font(FouleeFont.headline)
                    Text("Une carte sur l'accueil et un bouton « J'ai bu ». L'eau est enregistrée dans Santé.")
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(FouleeColor.water)
            if preferences.hydrationEnabled {
                SettingsField("Objectif quotidien") {
                    SettingsSlider(
                        title: "Objectif quotidien",
                        value: $preferences.hydrationGoalML,
                        range: 1_000...4_000,
                        step: 200,
                        tint: FouleeColor.water
                    ) { "\(litres($0)) L" }
                }
                SettingsField("Taille d'un verre", footer: "Chaque « J'ai bu » ajoute un verre.") {
                    SettingsSlider(
                        title: "Taille d'un verre",
                        value: $preferences.hydrationGlassML,
                        range: 50...500,
                        step: 10,
                        tint: FouleeColor.water
                    ) { "\($0) mL" }
                }
                Divider()
                HydrationReminderSettings(preferences: preferences)
            }
        }
    }
}
