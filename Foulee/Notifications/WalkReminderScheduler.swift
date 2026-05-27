import Dependencies
import Foundation

/// Computes the set of `WalkReminder`s implied by the current
/// `UserPreferences` and pushes them to `NotificationsClient`. Pure logic
/// helpers (`reminders(for:)`, `reminderTime(forWindowStart:)`) are
/// `static` so they can be unit-tested without spinning up the client.
struct WalkReminderScheduler {
    @Dependency(\.notifications) private var notifications

    /// Minutes before `walkWindowStart` the reminder fires.
    static let leadMinutes = 10

    /// Build the reminder time (start − 10 min, clamped to the same hour
    /// when the subtraction would cross midnight backwards).
    static func reminderTime(forWindowStart start: TimeOfDay) -> TimeOfDay {
        let raw = max(start.rawMinutes - leadMinutes, 0)
        return TimeOfDay(rawMinutes: raw)
    }

    /// Produce one reminder per active day of the week. `@MainActor` because
    /// `UserPreferences` is main-isolated. Returns an empty array when the
    /// user has flipped notifications off — the live client then wipes the
    /// pending queue on the next `sync(with:)`.
    @MainActor
    static func reminders(for preferences: UserPreferences) -> [WalkReminder] {
        guard preferences.notificationsEnabled else { return [] }
        let time = reminderTime(forWindowStart: preferences.walkWindowStart)
        return preferences.activeDays
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { day in
                WalkReminder(
                    weekday: day,
                    time: time,
                    title: "Foulée",
                    body: "C'est l'heure de bouger — direction la pause marche."
                )
            }
    }

    /// Push the current preferences' implied schedule to iOS. Safe to call
    /// repeatedly — the client replaces the previous Foulée requests.
    /// Single error boundary: a denied authorization (or any scheduling
    /// hiccup) is absorbed here; the Settings screen exposes the toggle
    /// the user would actually use to recover.
    @MainActor
    func sync(with preferences: UserPreferences) async {
        let reminders = Self.reminders(for: preferences)
        do {
            try await notifications.replaceWalkReminders(reminders)
        } catch {
            // Intentionally silent: there is no UX surface for a scheduling
            // failure at the moment the app launches.
        }
    }

    /// Add a one-shot reminder in `interval` seconds (bell-menu "Plus tard"
    /// actions). Independent of the recurring weekly schedule. Errors are
    /// absorbed — the bell visually flips to confirm the tap, that's the
    /// only feedback the user needs.
    @MainActor
    func snooze(after interval: TimeInterval) async {
        do {
            try await notifications.scheduleSnooze(interval)
        } catch {
            // Silent on purpose, see comment on `sync(with:)`.
        }
    }
}
