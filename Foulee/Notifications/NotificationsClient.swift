import Dependencies
import Foundation

/// Recurring weekly reminder description — one notification per `Weekday`
/// firing at `time` local. Identifier is derived so reschedules are
/// idempotent (replacing the old request for the same day).
struct WalkReminder: Equatable, Sendable {
    var weekday: Weekday
    var time: TimeOfDay
    var title: String
    var body: String

    var identifier: String {
        "foulee.walk.reminder.\(weekday.rawValue)"
    }
}

/// Wrapper over `UNUserNotificationCenter` with the operations the app
/// actually needs. Async/throws bubble up to the scheduler boundary; no
/// per-call try/catch sprinkled.
struct NotificationsClient: Sendable {
    var requestAuthorization: @Sendable () async throws -> Bool
    var replaceWalkReminders: @Sendable (_ reminders: [WalkReminder]) async throws -> Void

    /// One-shot reminder fired after `interval` seconds, independent of
    /// the recurring weekly schedule. Used by the bell "snooze" menu so
    /// the user can postpone today's walk without touching the rest of
    /// their schedule.
    var scheduleSnooze: @Sendable (_ after: TimeInterval) async throws -> Void

    /// Register the hydration notification category + its two actions
    /// ("J'ai bu" / "Rappelle-moi dans `snoozeMinutes` min"). Re-called when
    /// the snooze duration changes so the button label stays accurate.
    var configureHydrationCategory: @Sendable (_ snoozeMinutes: Int) async -> Void
        = { _ in }

    /// Replace the recurring hydration reminders with one daily-repeating
    /// notification per time slot. An empty array wipes them.
    var replaceHydrationReminders: @Sendable (_ times: [TimeOfDay]) async throws -> Void
        = { _ in }

    /// One-shot hydration reminder fired after `interval` seconds — the
    /// "Rappelle-moi" notification action.
    var scheduleHydrationSnooze: @Sendable (_ after: TimeInterval) async throws -> Void
        = { _ in }
}

extension NotificationsClient: DependencyKey {
    static let previewValue = NotificationsClient(
        requestAuthorization: { true },
        replaceWalkReminders: { _ in },
        scheduleSnooze: { _ in }
    )

    static let testValue = NotificationsClient(
        requestAuthorization: { false },
        replaceWalkReminders: { _ in },
        scheduleSnooze: { _ in }
    )
}

extension DependencyValues {
    var notifications: NotificationsClient {
        get { self[NotificationsClient.self] }
        set { self[NotificationsClient.self] = newValue }
    }
}
