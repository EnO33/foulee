import Dependencies
import SwiftUI

/// Settings — édite les mêmes prefs qu'onboarding + thème + notifs.
/// Présenté en sheet depuis le bouton profil de l'écran Aujourd'hui.
struct SettingsScreen: View {
    @Bindable var preferences: UserPreferences

    @State private var isShowingGarminGuide = false

    /// A sheet presented from a sheet doesn't inherit the theme — resolve it
    /// here, same as `TodayScreen` does for its own modals.
    @Environment(\.colorScheme) private var systemColorScheme

    private let appVersion: String = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                appearanceSection
                activitySection
                stepsSection
                hydrationSection
                notificationsSection
                watchSection
                aboutSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $isShowingGarminGuide) {
            GarminSetupSheet { isShowingGarminGuide = false }
                .preferredColorScheme(preferences.themeMode.colorScheme ?? systemColorScheme)
        }
    }

    /// The Garmin guide again, for the (common) case where the watch arrives
    /// long after the onboarding.
    private var watchSection: some View {
        section(title: "Montre") {
            GarminSetupLink { isShowingGarminGuide = true }
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

    /// Was `section(title: "Marche")` until #220: it groups the days, the time
    /// window and the minutes goal, which are the same three settings whatever
    /// the user moves at — naming it after one activity was what made the
    /// walk/run choice impossible to file anywhere.
    private var activitySection: some View {
        section(title: "Activité") {
            VStack(alignment: .leading, spacing: 20) {
                modeRow
                daysRow
                windowRow
                minutesGoalRow
            }
        }
    }

    /// The walk/run choice (#220). Segmented like the theme picker — three
    /// short labels, one tap, no drill-down; the layout below it is identical
    /// in all three modes, so nothing is disclosed conditionally.
    ///
    /// The footnote states the project's contract to the user, and it is the
    /// literal truth rather than reassurance: the streak, the record and the
    /// calendar count exercise minutes across every activity type and never
    /// read this preference, so switching here moves no history.
    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Activité", selection: $preferences.activityMode) {
                ForEach(ActivityMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text("Ta série compte toutes tes activités, quel que soit ce choix.")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Daily step goal — independent from the activity goal: it's tracked all
    /// day (the midday walk just contributes to it), so it stands on its own.
    private var stepsSection: some View {
        section(title: "Objectif de pas") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    rowLabel("Objectif quotidien")
                    Spacer()
                    Text("\(preferences.stepsGoal.formattedFR) pas")
                        .scaledNumericFont(size: 20, weight: .semibold)
                        .foregroundStyle(FouleeColor.accentMid)
                }
                Slider(
                    value: Binding(
                        get: { Double(preferences.stepsGoal) },
                        set: { preferences.stepsGoal = Int($0) }
                    ),
                    in: 2_000...15_000,
                    step: 500
                )
                .tint(FouleeColor.accentMid)
                Text("Compté toute la journée, ta marche du midi incluse.")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
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

    /// "Fenêtre horaire", not "Fenêtre de marche": this row now sits directly
    /// under a picker that can say "Course", and the old label would contradict
    /// it on screen. Deliberately the only copy touched here — the rest of the
    /// app's walking vocabulary is #222's sweep, not this issue's.
    private var windowRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowLabel("Fenêtre horaire")
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

    /// Activity goal — the midday-walk duration that drives the ring + the
    /// "start walk" flow. Distinct from the all-day step goal below.
    private var minutesGoalRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                rowLabel("Objectif d'activité")
                Spacer()
                Text("\(preferences.minutesGoal) min")
                    .scaledNumericFont(size: 20, weight: .semibold)
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

    private var hydrationSection: some View {
        section(title: "Hydratation") {
            HydrationSettingsContent(preferences: preferences)
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
            // The circle stays 40 pt (7 chips must fit one row), so the label
            // scales with Dynamic Type until it hits the circle, then shrinks.
            Text(day.shortLabel)
                .font(.system(.subheadline, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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
        defaults: UserDefaults(suiteName: "preview-settings") ?? .standard
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
