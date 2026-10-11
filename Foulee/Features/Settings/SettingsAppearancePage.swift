import SwiftUI

/// Apparence: the theme, applied to every screen and sheet.
struct SettingsAppearancePage: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        GlassSection("Thème", footer: "« Système » suit le réglage clair ou sombre de ton iPhone.") {
            Picker("Thème", selection: $preferences.themeMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
