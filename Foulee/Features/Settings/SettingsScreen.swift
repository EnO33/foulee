import SwiftUI

/// Réglages (issue #393): a home of summarised rows, each opening the page for
/// one theme. Presented as a sheet from the gear button of the Today screen.
///
/// A stack rather than one long scroll: every value reads at a glance on the
/// home, and changing one is a tap away instead of a hunt through eight cards.
struct SettingsScreen: View {
    @Bindable var preferences: UserPreferences
    var onClose: () -> Void

    @State private var isShowingGarminGuide = false

    /// A sheet presented from a sheet doesn't inherit the theme — resolve it
    /// here, same as `TodayScreen` does for its own modals.
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(eyebrow: "Foulée", title: "Réglages")
                    GlassSection {
                        link(.goals, summary: SettingsSummary.goals(
                            mode: preferences.activityMode,
                            minutesGoal: preferences.minutesGoal,
                            stepsGoal: preferences.stepsGoal
                        ))
                        Divider()
                        link(.schedule, summary: SettingsSummary.schedule(
                            days: preferences.activeDays,
                            start: preferences.walkWindowStart,
                            end: preferences.walkWindowEnd
                        ))
                        Divider()
                        link(.hydration, summary: SettingsSummary.hydration(
                            enabled: preferences.hydrationEnabled,
                            goalML: preferences.hydrationGoalML,
                            remindersEnabled: preferences.hydrationRemindersEnabled,
                            intervalMinutes: preferences.hydrationIntervalMinutes
                        ))
                    }
                    GlassSection {
                        link(.notifications, summary: SettingsSummary.notifications(
                            activeCount: preferences.activeReminderCount
                        ))
                        Divider()
                        link(.appearance, summary: preferences.themeMode.label)
                    }
                    GlassSection {
                        garminRow
                        Divider()
                        link(.about, summary: "Version, licence")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
            .overlay(alignment: .topTrailing) { SheetCloseButton(action: onClose) }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsPage.self) { page in
                SettingsPageView(page: page, preferences: preferences)
            }
        }
        .sheet(isPresented: $isShowingGarminGuide) {
            GarminSetupSheet { isShowingGarminGuide = false }
                .preferredColorScheme(preferences.themeMode.colorScheme ?? systemColorScheme)
        }
    }

    private func link(_ page: SettingsPage, summary: String) -> some View {
        NavigationLink(value: page) {
            SettingsRow(icon: page.icon, tint: page.tint, title: page.title, summary: summary)
        }
        .buttonStyle(.pressable)
    }

    /// The Garmin guide again, for the (common) case where the watch arrives
    /// long after the onboarding. A sheet straight away: a page holding a
    /// single link would only add a tap.
    private var garminRow: some View {
        Button { isShowingGarminGuide = true } label: {
            SettingsRow(
                icon: FouleeIcon.watch,
                tint: FouleeColor.accentEnd,
                title: "Montre Garmin",
                summary: "Activer la synchro vers Santé"
            )
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
            SettingsScreen(preferences: preferences) {}
        }
    }
}

#Preview("Light") { SettingsPreview().preferredColorScheme(.light) }
#Preview("Dark") { SettingsPreview().preferredColorScheme(.dark) }
