import SwiftUI

/// Notifications: every reminder the app can send, in one place.
struct SettingsNotificationsPage: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        GlassSection {
            reminderToggle(
                "Rappel avant ta sortie",
                detail: "10 minutes avant ta fenêtre, sur les jours actifs.",
                isOn: $preferences.notificationsEnabled
            )
            Divider()
            reminderToggle(
                "Récap de la semaine et du mois",
                detail: "Le lundi et le 1er du mois, à 9 h.",
                isOn: $preferences.recapNotificationsEnabled
            )
        }
    }

    private func reminderToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FouleeFont.headline)
                Text(detail)
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(FouleeColor.success)
    }
}
