import Dependencies
import Foundation

/// Turns the hydration prefs into a set of daily reminder times and pushes them
/// to `NotificationsClient`. `reminderTimes` is pure + static so it's unit
/// tested without the client.
struct HydrationReminderScheduler {
    @Dependency(\.notifications) private var notifications

    /// Times from `start` to `end` (inclusive) every `intervalMinutes`.
    /// Empty when the window is degenerate or the interval is non-positive.
    static func reminderTimes(start: TimeOfDay, end: TimeOfDay, intervalMinutes: Int) -> [TimeOfDay] {
        guard intervalMinutes > 0, end.rawMinutes >= start.rawMinutes else { return [] }
        var times: [TimeOfDay] = []
        var minutes = start.rawMinutes
        while minutes <= end.rawMinutes {
            times.append(TimeOfDay(rawMinutes: minutes))
            minutes += intervalMinutes
        }
        return times
    }

    /// Reminder times implied by the prefs — empty when hydration or its
    /// reminders are off (which wipes the pending queue on the next sync).
    @MainActor
    static func times(for preferences: UserPreferences) -> [TimeOfDay] {
        guard preferences.hydrationEnabled, preferences.hydrationRemindersEnabled else { return [] }
        return reminderTimes(
            start: preferences.hydrationWindowStart,
            end: preferences.hydrationWindowEnd,
            intervalMinutes: preferences.hydrationIntervalMinutes
        )
    }

    @MainActor
    func sync(with preferences: UserPreferences) async {
        await notifications.configureHydrationCategory(preferences.hydrationSnoozeMinutes)
        // Ensure notification permission when reminders are on (idempotent —
        // no re-prompt once the user has decided).
        if preferences.hydrationEnabled, preferences.hydrationRemindersEnabled {
            _ = try? await notifications.requestAuthorization()
        }
        do {
            try await notifications.replaceHydrationReminders(Self.times(for: preferences))
        } catch {
            // Silent on purpose: Settings exposes the toggle to recover.
        }
    }
}
