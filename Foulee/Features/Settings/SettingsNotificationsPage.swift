import SwiftUI

/// Notifications (issue #394): every reminder the app can send, in one place,
/// under what iOS actually allows — a toggle left on while iOS blocks Foulée
/// would otherwise promise a reminder that never comes.
struct SettingsNotificationsPage: View {
    @Bindable var preferences: UserPreferences
    /// Owned by `SettingsScreen`, so its home row reflects a grant made here.
    let store: NotificationPermissionStore

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            permissionBanner
            GlassSection {
                SettingsToggle(
                    "Rappel avant ta sortie",
                    detail: "10 minutes avant ta fenêtre, sur les jours actifs.",
                    isOn: $preferences.notificationsEnabled
                )
                Divider()
                SettingsToggle(
                    "Récap de la semaine et du mois",
                    detail: "Le dimanche à 19 h, et le 1er du mois à 9 h.",
                    isOn: $preferences.recapNotificationsEnabled
                )
                Divider()
                SettingsToggle(
                    "Après une séance",
                    detail: "Quand une sortie arrive de ta montre : rythme, records, régularité.",
                    isOn: $preferences.sessionNotificationsEnabled
                )
                if preferences.hydrationEnabled {
                    Divider()
                    hydrationReminder
                }
            }
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        switch store.permission {
        case .denied:
            SettingsBanner(
                message: "Les notifications de Foulée sont coupées dans iOS : aucun rappel ne peut arriver.",
                icon: "bell.slash.fill",
                action: "Ouvrir les réglages"
            ) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
        case .notDetermined:
            SettingsBanner(
                message: "Foulée n'a pas encore la permission de t'envoyer des rappels.",
                icon: "bell.slash.fill",
                action: "Autoriser"
            ) {
                Task { await store.request() }
            }
        case .unknown, .allowed:
            EmptyView()
        }
    }

    /// The water reminders' switch is the one in the Hydratation page too;
    /// their window and rhythm stay there, one tap away.
    private var hydrationReminder: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsToggle(
                "Rappels d'eau",
                detail: .verbatim(SettingsSummary.hydrationReminders(
                    start: preferences.hydrationWindowStart,
                    end: preferences.hydrationWindowEnd,
                    intervalMinutes: preferences.hydrationIntervalMinutes
                )),
                isOn: $preferences.hydrationRemindersEnabled
            )
            NavigationLink(value: SettingsPage.hydration) {
                Label("Régler la plage et la fréquence", systemImage: "slider.horizontal.3")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(FouleeColor.water)
            }
            .buttonStyle(.pressable)
        }
    }
}
