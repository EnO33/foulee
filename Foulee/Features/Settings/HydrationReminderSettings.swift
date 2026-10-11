import SwiftUI

/// Reminder controls inside the Hydratation settings page: an on/off toggle
/// and, when on, the time window + interval.
struct HydrationReminderSettings: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle(isOn: $preferences.hydrationRemindersEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rappels").font(FouleeFont.headline)
                    Text("Des notifications « Pense à boire » avec « J'ai bu » et « Rappelle-moi ».")
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(HydrationCard.water)
            if preferences.hydrationRemindersEnabled {
                SettingsField("Plage horaire") {
                    TimeWindowPicker(start: $preferences.hydrationWindowStart, end: $preferences.hydrationWindowEnd)
                }
                SettingsField("Fréquence") {
                    SettingsSlider(
                        title: "Fréquence des rappels",
                        value: $preferences.hydrationIntervalMinutes,
                        range: 20...240,
                        step: 10,
                        tint: HydrationCard.water
                    ) { "toutes les \(durationText(minutes: $0))" }
                }
            }
        }
    }
}
