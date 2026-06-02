import Dependencies
import SwiftUI

/// Settings — édite les mêmes prefs qu'onboarding + thème + notifs.
/// Présenté en sheet depuis le bouton profil de l'écran Aujourd'hui.
struct SettingsScreen: View {
    @Bindable var preferences: UserPreferences

    private let appVersion: String = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                appearanceSection
                walkSection
                notificationsSection
                aboutSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RÉGLAGES")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text("Préférences")
                .font(FouleeFont.largeTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceSection: some View {
        section(title: "Apparence") {
            Picker("Thème", selection: $preferences.themeMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var walkSection: some View {
        section(title: "Marche") {
            VStack(alignment: .leading, spacing: 20) {
                daysRow
                windowRow
                goalRow
            }
        }
    }

    private var daysRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowLabel("Jours actifs")
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

    private var windowRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowLabel("Fenêtre de marche")
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

    private var goalRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                rowLabel("Objectif")
                Spacer()
                Text("\(preferences.minutesGoal) min")
                    .font(FouleeFont.numeric(size: 20, weight: .semibold))
                    .foregroundStyle(FouleeColor.accentMid)
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
        }
    }

    private var notificationsSection: some View {
        section(title: "Notifications") {
            Toggle(isOn: $preferences.notificationsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rappel avant la marche")
                        .font(FouleeFont.headline)
                    Text("10 minutes avant ta fenêtre, sur les jours actifs.")
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(FouleeColor.success)
        }
    }

    private var aboutSection: some View {
        section(title: "À propos") {
            VStack(alignment: .leading, spacing: 12) {
                aboutRow(label: "Version", value: appVersion)
                aboutRow(label: "Auteur", value: "EnO33")
                aboutRow(label: "Licence", value: "MIT")
            }
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(FouleeFont.body)
            Spacer()
            Text(value).font(FouleeFont.body).foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
                .padding(.horizontal, 4)
            content()
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fouleeGlass(cornerRadius: 22)
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(FouleeFont.headline)
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

/// Round day chip used by the days row. Lifted out so the look stays
/// consistent with `OnboardingGoalView` without duplicating the gradient
/// styling inline.
struct DayChip: View {
    var day: Weekday
    var active: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Text(day.shortLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(active ? AnyShapeStyle(FouleeColor.accentGradient) : AnyShapeStyle(Color.clear))
                )
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(active ? 0 : 0.25), lineWidth: 1)
                )
                .shadow(color: FouleeColor.accentMid.opacity(active ? 0.35 : 0), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.pressable)
    }
}

private struct SettingsPreview: View {
    @State private var preferences = UserPreferences(
        defaults: UserDefaults(suiteName: "preview-settings")!
    )
    var body: some View {
        ZStack {
            Wallpaper()
            SettingsScreen(preferences: preferences)
        }
    }
}

#Preview("Light") { SettingsPreview().preferredColorScheme(.light) }
#Preview("Dark") { SettingsPreview().preferredColorScheme(.dark) }
