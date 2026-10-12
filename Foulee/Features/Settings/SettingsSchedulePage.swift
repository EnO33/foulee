import FouleeKit
import SwiftUI

/// Planning: the days and the time window the reminders and the streak follow.
struct SettingsSchedulePage: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        GlassSection("Jours actifs", footer: "Un jour non coché ne casse jamais ta série.") {
            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { day in
                    DayChip(
                        day: day,
                        active: preferences.activeDays.contains(day),
                        toggle: { toggle(day: day) }
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        // « Fenêtre horaire », not « Fenêtre de marche »: the same single
        // window serves walking, running or both (#222).
        GlassSection("Fenêtre horaire", footer: "Le rappel de sortie arrive 10 minutes avant son début.") {
            TimeWindowPicker(start: $preferences.walkWindowStart, end: $preferences.walkWindowEnd)
        }
    }

    private func toggle(day: Weekday) {
        if preferences.activeDays.contains(day) {
            preferences.activeDays.remove(day)
        } else {
            preferences.activeDays.insert(day)
        }
    }
}
