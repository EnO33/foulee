import Dependencies
import Foundation

/// Turns the hydration prefs into a set of daily reminder times and pushes them
/// to `NotificationsClient`. `reminderTimes` is pure + static so it's unit
/// tested without the client.
struct HydrationReminderScheduler {
    @Dependency(\.notifications) private var notifications

    /// UserDefaults key holding the unix time of the last logged glass — used
    /// to shift the grid so a reminder never lands minutes after a drink.
    static let lastDrinkKey = "hydration.lastDrinkAt"

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

    /// Grid that accounts for the last glass of the day: the next reminder is
    /// a full interval after the drink, then every interval until `end`.
    /// Falls back to the standard grid when the drink doesn't constrain it
    /// (no drink, drink early enough, or drink so late the shifted grid would
    /// be empty — the repeating triggers must survive for tomorrow).
    static func reminderTimes(
        start: TimeOfDay,
        end: TimeOfDay,
        intervalMinutes: Int,
        lastDrink: TimeOfDay?
    ) -> [TimeOfDay] {
        let standard = reminderTimes(start: start, end: end, intervalMinutes: intervalMinutes)
        guard let lastDrink, intervalMinutes > 0 else { return standard }
        let anchor = lastDrink.rawMinutes + intervalMinutes
        guard anchor > start.rawMinutes, anchor <= end.rawMinutes else { return standard }
        var times: [TimeOfDay] = []
        var minutes = anchor
        while minutes <= end.rawMinutes {
            times.append(TimeOfDay(rawMinutes: minutes))
            minutes += intervalMinutes
        }
        return times
    }

    /// The last logged glass as a time-of-day — only if it happened today
    /// (yesterday's drink must not shift today's grid).
    static func lastDrinkToday(defaults: UserDefaults = .standard, now: Date = .now) -> TimeOfDay? {
        let timestamp = defaults.double(forKey: lastDrinkKey)
        guard timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: timestamp)
        guard Calendar.current.isDate(date, inSameDayAs: now) else { return nil }
        return TimeOfDay(date: date)
    }

    /// Reminder times implied by the prefs — empty when hydration or its
    /// reminders are off (which wipes the pending queue on the next sync).
    @MainActor
    static func times(for preferences: UserPreferences) -> [TimeOfDay] {
        guard preferences.hydrationEnabled, preferences.hydrationRemindersEnabled else { return [] }
        return reminderTimes(
            start: preferences.hydrationWindowStart,
            end: preferences.hydrationWindowEnd,
            intervalMinutes: preferences.hydrationIntervalMinutes,
            lastDrink: lastDrinkToday()
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

    /// Record a glass drunk *now* and shift today's grid so the next reminder
    /// lands a full interval later — instead of firing minutes after the
    /// drink. Reads the prefs straight from UserDefaults so it's callable from
    /// the background notification handler too (keys mirror `UserPreferences`).
    func recordDrinkAndReschedule(defaults: UserDefaults = .standard, now: Date = .now) async {
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastDrinkKey)
        let enabled = defaults.bool(forKey: "preferences.hydrationEnabled")
            && defaults.bool(forKey: "preferences.hydrationRemindersEnabled")
        guard enabled else { return }
        let startRaw = defaults.object(forKey: "preferences.hydrationWindowStart") as? Int ?? 9 * 60
        let endRaw = defaults.object(forKey: "preferences.hydrationWindowEnd") as? Int ?? 21 * 60
        let interval = defaults.object(forKey: "preferences.hydrationIntervalMinutes") as? Int ?? 120
        let times = Self.reminderTimes(
            start: TimeOfDay(rawMinutes: startRaw),
            end: TimeOfDay(rawMinutes: endRaw),
            intervalMinutes: interval,
            lastDrink: Self.lastDrinkToday(defaults: defaults, now: now)
        )
        try? await notifications.replaceHydrationReminders(times)
    }
}
