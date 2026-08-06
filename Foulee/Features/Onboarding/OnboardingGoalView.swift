import SwiftUI

/// Third onboarding screen — pick walk days, time window and minutes
/// goal. All edits land in `UserPreferences` immediately (no save button).
struct OnboardingGoalView: View {
    @Bindable var preferences: UserPreferences
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingStepIndicator(step: .goal)
                .frame(maxWidth: .infinity)
            heading
            daysSection
            windowSection
            goalSection
            Spacer()
            PrimaryButton(title: "Continuer", systemIcon: nil, action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 70)
        .padding(.bottom, 36)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quand veux-tu\nmarcher ?")
                .scaledSystemFont(size: 30, weight: .bold)
                .lineSpacing(2)
            Text("On t'enverra un petit rappel juste avant.")
                .font(FouleeFont.body)
                .foregroundStyle(.secondary)
        }
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Jours")
            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { day in
                    DayChip(
                        day: day,
                        active: preferences.activeDays.contains(day),
                        toggle: { toggle(day: day) }
                    )
                }
            }
        }
    }

    private func toggle(day: Weekday) {
        if preferences.activeDays.contains(day) {
            preferences.activeDays.remove(day)
        } else {
            preferences.activeDays.insert(day)
        }
    }

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Fenêtre")
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
                    .frame(width: 60, height: 2)
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
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .fouleeGlass(cornerRadius: 18)
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
                .scaledNumericFont(size: 22, weight: .semibold)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Objectif quotidien")
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(preferences.minutesGoal)")
                        .scaledNumericFont(size: 44)
                    Text("minutes")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(preferences.minutesGoal) },
                        set: { preferences.minutesGoal = Int($0) }
                    ),
                    in: 10...60,
                    step: 5
                )
                .tint(FouleeColor.accentMid)
                HStack {
                    Text("10 min").font(FouleeFont.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("60 min").font(FouleeFont.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .fouleeGlass(cornerRadius: 18)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(FouleeFont.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(1)
    }
}

extension TimeOfDay {
    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}
