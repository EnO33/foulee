import Foundation
@preconcurrency import UserNotifications

extension NotificationsClient {
    /// `UNUserNotificationCenter`-backed implementation. `replaceWalkReminders`
    /// always wipes the previous Foulée requests first so the user's pending
    /// queue can't drift out of sync with their preferences.
    static let liveValue: NotificationsClient = {
        let center = UNUserNotificationCenter.current()
        return NotificationsClient(
            requestAuthorization: {
                try await center.requestAuthorization(options: [.alert, .sound, .badge])
            },
            replaceWalkReminders: { reminders in
                let existing = await center.pendingNotificationRequests()
                let toRemove = existing
                    .map(\.identifier)
                    .filter { $0.hasPrefix("foulee.walk.reminder.") }
                center.removePendingNotificationRequests(withIdentifiers: toRemove)

                for reminder in reminders {
                    let content = UNMutableNotificationContent()
                    content.title = reminder.title
                    content.body = reminder.body
                    content.sound = .default

                    var components = DateComponents()
                    components.hour = reminder.time.hour
                    components.minute = reminder.time.minute
                    components.weekday = appleWeekday(from: reminder.weekday)

                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: components,
                        repeats: true
                    )
                    let request = UNNotificationRequest(
                        identifier: reminder.identifier,
                        content: content,
                        trigger: trigger
                    )
                    try await center.add(request)
                }
            },
            pendingReminderIdentifiers: {
                let pending = await center.pendingNotificationRequests()
                return pending
                    .map(\.identifier)
                    .filter { $0.hasPrefix("foulee.walk.reminder.") }
                    .sorted()
            },
            scheduleSnooze: { interval in
                let content = UNMutableNotificationContent()
                content.title = "Foulée"
                content.body = "C'est l'heure de bouger — direction la pause marche."
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: interval,
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "foulee.walk.snooze.\(Date().timeIntervalSince1970)",
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
            }
        )
    }()
}

/// Foulée's `Weekday` is Mon = 1, Apple's is Sun = 1. Translate.
private func appleWeekday(from day: Weekday) -> Int {
    switch day {
    case .sunday: 1
    case .monday: 2
    case .tuesday: 3
    case .wednesday: 4
    case .thursday: 5
    case .friday: 6
    case .saturday: 7
    }
}
