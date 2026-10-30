import FouleeKit
import SwiftUI

/// Third onboarding screen — pick active days, time window and minutes
/// goal. All edits land in `UserPreferences` immediately (no save button).
struct OnboardingGoalView: View {
    @Bindable var preferences: UserPreferences
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Scrolled like the activity and permissions screens. As a fixed
            // stack, three sections and their heading ran taller than an
            // iPhone SE: the title was cut to « Quand veux-tu… » and
            // « Continuer » slid half off the bottom of the screen.
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    OnboardingStepIndicator(step: .goal)
                        .frame(maxWidth: .infinity)
                    heading
                    daysSection
                    windowSection
                    goalSection
                }
                .screenColumn(gutter: 24)
                .padding(.top, 70)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            PrimaryButton(title: "Continuer", systemIcon: nil, action: onContinue)
                .screenColumn(gutter: 24)
                .padding(.bottom, 36)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "bouger", not "marcher": this screen comes right after the user
            // may have answered "Course" (#221/#222), and the window it sets
            // is the same one whatever they picked.
            Text("Quand veux-tu\nbouger ?")
                .scaledSystemFont(size: 30, weight: .bold)
                .lineSpacing(2)
                .accessibilityAddTraits(.isHeader)
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
            TimeWindowPicker(start: $preferences.walkWindowStart, end: $preferences.walkWindowEnd)
                .scaledNumericFont(size: 22, weight: .semibold)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .fouleeGlass(cornerRadius: 18)
        }
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
                // The slider below says it, as its value.
                .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { Double(preferences.minutesGoal) },
                        set: { preferences.minutesGoal = Int($0) }
                    ),
                    in: 10...60,
                    step: 5
                ) {
                    Text("Objectif quotidien")
                }
                .tint(FouleeColor.accentMid)
                .accessibilityValue("\(preferences.minutesGoal) minutes")
                HStack {
                    Text("10 min").font(FouleeFont.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("60 min").font(FouleeFont.caption).foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
            }
            .padding(18)
            .fouleeGlass(cornerRadius: 18)
        }
    }

    private func sectionLabel(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .textCase(.uppercase)
            .font(FouleeFont.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(1)
    }
}
