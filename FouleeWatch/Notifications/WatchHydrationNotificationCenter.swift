@preconcurrency import HealthKit
@preconcurrency import UserNotifications
import WidgetKit

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
final class WatchHydrationNotificationCenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = WatchHydrationNotificationCenter()

    private let store = HKHealthStore()
    private static let waterType = HKQuantityType(.dietaryWater)

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Register the same category + action identifiers as the phone, so
        // watchOS knows it can deliver the tap here instead of only opening
        // the app. Titles mirror the phone's.
        let drank = UNNotificationAction(
            identifier: HydrationNotification.drankAction,
            title: "J'ai bu",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: HydrationNotification.snoozeAction,
            title: "Rappelle-moi",
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
            await logGlass()
        case HydrationNotification.snoozeAction:
            await scheduleSnooze()
        default:
            break
        }
    }

    /// Log one glass (the phone-synced glass size) to the watch's HealthKit,
    /// then nudge the home to re-read so the card + haptic reflect it. A
    /// denied authorization or a failed save posts the matching failure
    /// signal instead — the glass didn't count, and only `WatchTodayStore`
    /// can say so on the card.
    private func logGlass() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        _ = try? await store.requestAuthorization(toShare: [Self.waterType], read: [Self.waterType])
        guard store.authorizationStatus(for: Self.waterType) != .sharingDenied else {
            await Self.post(.watchHydrationActionDenied)
            return
        }
        let glassML = WatchSyncStore.read()?.hydrationGlassML ?? 250
        let sample = HKQuantitySample(
            type: Self.waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(glassML)),
            start: .now,
            end: .now
        )
        do {
            try await store.save(sample)
        } catch {
            await Self.post(.watchHydrationActionFailed)
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
        await Self.post(HydrationNotification.actionHandled)
    }

    /// Observers rely on these signals arriving on the main actor.
    private static func post(_ name: Notification.Name) async {
        await MainActor.run {
            NotificationCenter.default.post(name: name, object: nil)
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
