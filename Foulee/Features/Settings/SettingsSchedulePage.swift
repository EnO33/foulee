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
            HStack(spacing: 16) {
                timePicker(
                    label: "Début",
                    selection: Binding(
                        get: { preferences.walkWindowStart.dateToday() },
                        set: { preferences.walkWindowStart = TimeOfDay(date: $0) }
                    )
                )
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 2)
                    .clipShape(Capsule())
                timePicker(
                    label: "Fin",
                    alignment: .trailing,
                    selection: Binding(
                        get: { preferences.walkWindowEnd.dateToday() },
                        set: { preferences.walkWindowEnd = TimeOfDay(date: $0) }
                    )
                )
            }
        }
    }

    private func timePicker(
        label: String,
        alignment: HorizontalAlignment = .leading,
        selection: Binding<Date>
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label)
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private func toggle(day: Weekday) {
        if preferences.activeDays.contains(day) {
            preferences.activeDays.remove(day)
        } else {
            preferences.activeDays.insert(day)
        }
    }
}
