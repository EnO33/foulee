import Foundation
import Testing
@testable import Foulee

@Suite("SettingsSummary")
struct SettingsSummaryTests {
    @Test("Goals read mode, minutes and steps")
    func goals() {
        #expect(SettingsSummary.goals(mode: .walking, minutesGoal: 20, stepsGoal: 6_000)
            == "Marche · 20 min · \(6_000.formattedFR) pas")
        #expect(SettingsSummary.goals(mode: .both, minutesGoal: 60, stepsGoal: 10_000)
            == "Les deux · 1 h · \(10_000.formattedFR) pas")
    }

    @Test("Usual day sets are named, others counted", arguments: [
        (Set<Weekday>(), "Aucun jour"),
        (Set(Weekday.allCases), "Tous les jours"),
        (Weekday.workWeek, "En semaine"),
        ([.saturday, .sunday], "Le week-end"),
        ([.wednesday], "Le mercredi"),
        ([.monday, .wednesday, .friday], "3 jours")
    ] as [(Set<Weekday>, String)])
    func days(days: Set<Weekday>, expected: String) {
        #expect(SettingsSummary.daysText(days) == expected)
    }

    @Test("Schedule joins the days and the window")
    func schedule() {
        let summary = SettingsSummary.schedule(
            days: Weekday.workWeek,
            start: TimeOfDay(hour: 11, minute: 30),
            end: TimeOfDay(hour: 9, minute: 5)
        )
        #expect(summary == "En semaine · 11:30–09:05")
    }

    @Test("Hydration says off, the goal, then the reminder rhythm")
    func hydration() {
        #expect(SettingsSummary.hydration(enabled: false, goalML: 2_000, remindersEnabled: true, intervalMinutes: 120)
            == "Désactivée")
        #expect(SettingsSummary.hydration(enabled: true, goalML: 2_000, remindersEnabled: false, intervalMinutes: 120)
            == "2,0 L")
        #expect(SettingsSummary.hydration(enabled: true, goalML: 2_400, remindersEnabled: true, intervalMinutes: 90)
            == "2,4 L · rappel toutes les 1 h 30")
    }

    @Test("Water reminders say their rhythm and window")
    func hydrationReminders() {
        let text = SettingsSummary.hydrationReminders(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 21, minute: 0),
            intervalMinutes: 120
        )
        #expect(text == "Toutes les 2 h, de 09:00 à 21:00.")
    }

    @Test("Notifications count with the right plural", arguments: [
        (0, "Aucun rappel"),
        (1, "1 rappel actif"),
        (3, "3 rappels actifs")
    ] as [(Int, String)])
    func notifications(count: Int, expected: String) {
        #expect(SettingsSummary.notifications(activeCount: count) == expected)
    }

    @Test("Notifications blocked in iOS say so, whatever the toggles")
    func notificationsBlocked() {
        #expect(SettingsSummary.notifications(activeCount: 3, blockedByIOS: true) == "Coupées dans iOS")
    }

    /// Water reminders only fire while hydration tracking is on, so they only
    /// count then — the summary must not promise a reminder that never comes.
    @Test("Water reminders count only while hydration is on")
    @MainActor
    func activeReminderCount() {
        let prefs = UserPreferences(defaults: UserDefaults(suiteName: "settings-summary-\(UUID())") ?? .standard)
        prefs.notificationsEnabled = true
        prefs.recapNotificationsEnabled = true
        prefs.hydrationRemindersEnabled = true
        prefs.hydrationEnabled = false
        #expect(prefs.activeReminderCount == 2)
        prefs.hydrationEnabled = true
        #expect(prefs.activeReminderCount == 3)
        prefs.notificationsEnabled = false
        #expect(prefs.activeReminderCount == 2)
    }
}
