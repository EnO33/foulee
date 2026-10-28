import FouleeKit
@preconcurrency import HealthKit
@preconcurrency import UserNotifications

extension Notification.Name {
    /// Posted (on the main actor) when the "J'ai bu" notification action could
    /// not save the glass — `WatchTodayStore` owns the card state and would
    /// otherwise never learn.
    static let watchHydrationActionFailed = Notification.Name("watchHydrationActionFailed")
    /// Posted (on the main actor) when the action found water writes denied in
    /// Health, so the card explains the denial instead of showing a dead button.
    static let watchHydrationActionDenied = Notification.Name("watchHydrationActionDenied")
}

/// Handles taps on the hydration reminder's actions when the banner is shown on
/// the **watch** (the phone forwards it there when the wrist is up). Without a
/// delegate *and* the matching category registered on the watch, watchOS just
/// opens the app on a "J'ai bu" tap and the glass is never logged — which is
/// exactly the bug this fixes. Mirrors the phone's `HydrationNotificationCenter`
/// but writes to the watch's own HealthKit (which syncs back to the phone).
/// Set as the delegate once at launch (`FouleeWatchApp.init`).
///
/// `@unchecked Sendable` because an `NSObject` subclass can never be checked
/// `Sendable` (issue #405); its only stored property is an
/// immutable `HKHealthStore`.
final class WatchHydrationNotificationCenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = WatchHydrationNotificationCenter()

    private let store = HKHealthStore()

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Register the same category + action identifiers as the phone, so
        // watchOS knows it can deliver the tap here instead of only opening
        // the app. Titles mirror the phone's.
        let drank = UNNotificationAction(
            identifier: HydrationNotification.drankAction,
            title: String(localized: "J'ai bu"),
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: HydrationNotification.snoozeAction,
            title: String(localized: "Rappelle-moi"),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: HydrationNotification.category,
            actions: [drank, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Show the banner if the watch app is already frontmost when it fires.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let completion = UncheckedSendableBox(completionHandler)
        Task {
            await handle(action: action)
            await MainActor.run { completion.value() }
        }
    }

    private func handle(action: String) async {
        switch action {
        case HydrationNotification.drankAction:
            _ = await WatchWaterLog.logGlass(store: store)
        case HydrationNotification.snoozeAction:
            await scheduleSnooze()
        default:
            break
        }
    }

    /// "Rappelle-moi" → a one-off local reminder on the watch after ~15 min
    /// (the phone owns the recurring schedule; this is just the snooze).
    private func scheduleSnooze() async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = HydrationNotification.title
        content.body = HydrationNotification.snoozeBody
        content.categoryIdentifier = HydrationNotification.category
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: HydrationNotification.snoozePrefix + "watch",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
