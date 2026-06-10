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
            },
            configureHydrationCategory: { snoozeMinutes in
                // .foreground: the action brings the app up with a valid window
                // scene. Without it iOS handles the tap in a "Non UI" background
                // launch, then asserts trying to snapshot the (sceneless) app for
                // state restoration → SIGABRT. Foreground sidesteps that entirely.
                let drank = UNNotificationAction(
                    identifier: HydrationNotification.drankAction,
                    title: "J'ai bu",
                    options: [.foreground]
                )
                let snooze = UNNotificationAction(
                    identifier: HydrationNotification.snoozeAction,
                    title: "Rappelle-moi dans \(snoozeMinutes) min",
                    options: [.foreground]
                )
                let category = UNNotificationCategory(
                    identifier: HydrationNotification.category,
                    actions: [drank, snooze],
                    intentIdentifiers: [],
                    options: []
                )
                center.setNotificationCategories([category])
            },
            replaceHydrationReminders: { times in
                let existing = await center.pendingNotificationRequests()
                let toRemove = existing
                    .map(\.identifier)
                    .filter { $0.hasPrefix(HydrationNotification.reminderPrefix) }
                center.removePendingNotificationRequests(withIdentifiers: toRemove)

                for time in times {
                    let content = UNMutableNotificationContent()
                    content.title = HydrationNotification.title
                    content.body = HydrationNotification.body
                    content.sound = .default
                    content.categoryIdentifier = HydrationNotification.category

                    var components = DateComponents()
                    components.hour = time.hour
                    components.minute = time.minute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "\(HydrationNotification.reminderPrefix)\(time.rawMinutes)",
                        content: content,
                        trigger: trigger
                    )
                    try await center.add(request)
                }
            },
            scheduleHydrationSnooze: { interval in
                let content = UNMutableNotificationContent()
                content.title = HydrationNotification.title
                content.body = HydrationNotification.snoozeBody
                content.sound = .default
                content.categoryIdentifier = HydrationNotification.category

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(HydrationNotification.snoozePrefix)\(Date().timeIntervalSince1970)",
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
