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
    var pendingReminderIdentifiers: @Sendable () async -> [String]

    /// One-shot reminder fired after `interval` seconds, independent of
    /// the recurring weekly schedule. Used by the bell "snooze" menu so
    /// the user can postpone today's walk without touching the rest of
    /// their schedule.
    var scheduleSnooze: @Sendable (_ after: TimeInterval) async throws -> Void
}

extension NotificationsClient: DependencyKey {
    static let previewValue = NotificationsClient(
        requestAuthorization: { true },
        replaceWalkReminders: { _ in },
        pendingReminderIdentifiers: { [] },
        scheduleSnooze: { _ in }
    )

    static let testValue = NotificationsClient(
        requestAuthorization: { false },
        replaceWalkReminders: { _ in },
        pendingReminderIdentifiers: { [] },
        scheduleSnooze: { _ in }
    )
}

extension DependencyValues {
    var notifications: NotificationsClient {
        get { self[NotificationsClient.self] }
        set { self[NotificationsClient.self] = newValue }
    }
}
