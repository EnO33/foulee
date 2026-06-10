import SwiftUI

/// Reminder controls inside the Settings "Hydratation" section: an on/off
/// toggle and, when on, the time window + interval. Its own view so the parent
/// bodies stay within the lint limits.
struct HydrationReminderSettings: View {
    @Bindable var preferences: UserPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $preferences.hydrationRemindersEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rappels").font(FouleeFont.headline)
                    Text("Des notifications « Pense à boire » avec « J'ai bu » et « Rappelle-moi ».")
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.teal)
            if preferences.hydrationRemindersEnabled {
                windowRow
                intervalRow
            }
        }
    }

    private var windowRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plage horaire").font(FouleeFont.headline)
            HStack(spacing: 16) {
                timePicker(alignment: .leading, selection: Binding(
                    get: { preferences.hydrationWindowStart.dateToday() },
                    set: { preferences.hydrationWindowStart = TimeOfDay(date: $0) }
                ))
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 2)
                    .clipShape(Capsule())
                timePicker(alignment: .trailing, selection: Binding(
                    get: { preferences.hydrationWindowEnd.dateToday() },
                    set: { preferences.hydrationWindowEnd = TimeOfDay(date: $0) }
                ))
            }
        }
    }

    private var intervalRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fréquence").font(FouleeFont.headline)
                Spacer()
                Text("toutes les \(intervalLabel(preferences.hydrationIntervalMinutes))")
                    .font(FouleeFont.numeric(size: 18, weight: .semibold))
                    .foregroundStyle(.teal)
            }
            Slider(
                value: Binding(
                    get: { Double(preferences.hydrationIntervalMinutes) },
                    set: { preferences.hydrationIntervalMinutes = Int($0) }
                ),
                in: 20...240,
                step: 10
            )
            .tint(.teal)
        }
    }

    private func timePicker(alignment: HorizontalAlignment, selection: Binding<Date>) -> some View {
        DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    /// Minutes → "30 min" / "1 h" / "1 h 30".
    private func intervalLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins) min" }
        if mins == 0 { return "\(hours) h" }
        return "\(hours) h \(mins)"
    }
}
