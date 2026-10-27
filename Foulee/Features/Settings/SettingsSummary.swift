import FouleeKit
import Foundation

/// The one-line values the Réglages home prints under each row (issue #393),
/// so a setting can be read without opening its page. Pure functions of plain
/// values: the wording is pinned by tests, not by screenshots.
enum SettingsSummary {
    /// « Marche · 20 min · 6 000 pas ».
    static func goals(mode: ActivityMode, minutesGoal: Int, stepsGoal: Int) -> String {
        String(localized: "\(mode.label) · \(durationText(minutes: minutesGoal)) · \(stepsGoal.groupedText()) pas")
    }

    /// « En semaine · 11:30–13:30 ».
    static func schedule(days: Set<Weekday>, start: TimeOfDay, end: TimeOfDay) -> String {
        "\(daysText(days)) · \(start.clockText)–\(end.clockText)"
    }

    /// The active days in words, the usual sets by name.
    static func daysText(_ days: Set<Weekday>) -> String {
        switch days {
        case []: String(localized: "Aucun jour")
        case Set(Weekday.allCases): String(localized: "Tous les jours")
        case Weekday.workWeek: String(localized: "En semaine")
        case [.saturday, .sunday]: String(localized: "Le week-end")
        default:
            if days.count == 1, let day = days.first {
                String(localized: "Le \(day.fullName)")
            } else {
                String(localized: "\(days.count) jours")
            }
        }
    }

    /// « 2,0 L · rappel toutes les 2 h », « 2,0 L », or « Désactivée ».
    static func hydration(enabled: Bool, goalML: Int, remindersEnabled: Bool, intervalMinutes: Int) -> String {
        guard enabled else { return String(localized: "Désactivée") }
        let goal = "\(litres(goalML)) L"
        return remindersEnabled
            ? String(localized: "\(goal) · rappel toutes les \(durationText(minutes: intervalMinutes))")
            : goal
    }

    /// « Toutes les 2 h, de 09:00 à 21:00 ».
    static func hydrationReminders(start: TimeOfDay, end: TimeOfDay, intervalMinutes: Int) -> String {
        String(localized: "Toutes les \(durationText(minutes: intervalMinutes)), de \(start.clockText) à \(end.clockText).")
    }

    /// « Aucun rappel », « 1 rappel actif », « 3 rappels actifs » — or
    /// « Coupées dans iOS » when no reminder can arrive whatever the toggles
    /// say (#394).
    static func notifications(activeCount: Int, blockedByIOS: Bool = false) -> String {
        if blockedByIOS { return String(localized: "Coupées dans iOS") }
        return activeCount > 0 ? String(localized: "\(activeCount) rappels actifs") : String(localized: "Aucun rappel")
    }
}

extension UserPreferences {
    /// Reminders that will actually be scheduled: water ones only count while
    /// hydration tracking itself is on, as `HydrationReminderScheduler` does.
    var activeReminderCount: Int {
        [
            notificationsEnabled,
            recapNotificationsEnabled,
            sessionNotificationsEnabled,
            hydrationEnabled && hydrationRemindersEnabled
        ]
            .filter { $0 }
            .count
    }
}
