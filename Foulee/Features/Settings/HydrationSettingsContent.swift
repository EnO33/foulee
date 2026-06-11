import SwiftUI

/// The contents of the Settings "Hydratation" section — the on/off toggle and,
/// when on, the daily goal + glass-size sliders. Split out of `SettingsScreen`
/// to keep that view's body within bounds.
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
            .tint(.teal)
            if preferences.hydrationEnabled {
                goalRow
                glassRow
                Divider().overlay(Color.white.opacity(0.08))
                HydrationReminderSettings(preferences: preferences)
            }
        }
    }

    private var goalRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Objectif quotidien").font(FouleeFont.headline)
                Spacer()
                Text("\(litres(preferences.hydrationGoalML)) L")
                    .font(FouleeFont.numeric(size: 20, weight: .semibold))
                    .foregroundStyle(.teal)
            }
            Slider(
                value: Binding(
                    get: { Double(preferences.hydrationGoalML) },
                    set: { preferences.hydrationGoalML = Int($0) }
                ),
                in: 1_000...4_000,
                step: 200
            )
            .tint(.teal)
        }
    }

    private var glassRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Taille d'un verre").font(FouleeFont.headline)
                Spacer()
                Text("\(preferences.hydrationGlassML) mL")
                    .font(FouleeFont.numeric(size: 20, weight: .semibold))
                    .foregroundStyle(.teal)
            }
            Slider(
                value: Binding(
                    get: { Double(preferences.hydrationGlassML) },
                    set: { preferences.hydrationGlassML = Int($0) }
                ),
                in: 50...500,
                step: 10
            )
            .tint(.teal)
            Text("Chaque « J'ai bu » ajoute un verre.")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
