@preconcurrency import UserNotifications
import WidgetKit

/// Handles taps on the hydration reminder's actions. iOS launches the app in
/// the background to run these, so we read the live prefs and write straight to
/// Health / reschedule — no UI needed. Set as the notification-center delegate
/// once at launch (`FouleeApp.init`).
///
/// Uses the completion-handler delegate methods (not the `async` variants):
/// the async forms proved crash-prone here, and the completion-handler form is
/// the long-stable contract — we just hop the real work onto a `Task`.
final class HydrationNotificationCenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = HydrationNotificationCenter()

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show hydration banners even when the app is in the foreground.
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
        // The completion handler isn't Sendable; box it so it can cross into
        // the Task. Safe — it's invoked exactly once when the work finishes.
        let completion = UncheckedSendableBox(completionHandler)
        Task {
            await Self.handle(action: action)
            // The system's completion synchronously runs UIKit snapshot/state-
            // restoration work on the calling thread, which asserts off-main
            // (SIGABRT in _performBlockAfterCATransactionCommitSynchronizes —
            // crash reports builds 93/95). Always deliver it on the main thread.
            await MainActor.run { completion.value() }
        }
    }

    private static func handle(action: String) async {
        // iOS wakes the app in the *background* to run this. Read prefs straight
        // from UserDefaults — don't spin up a `@MainActor @Observable`
        // UserPreferences here (heavy + a likely crash source in a background
        // launch). Keys mirror `UserPreferences.Keys`.
        let defaults = UserDefaults.standard
        switch action {
        case HydrationNotification.drankAction:
            // "J'ai bu" → log one glass to Health; the reminder is dismissed
            // by the system automatically.
            let glassML = defaults.object(forKey: "preferences.hydrationGlassML") as? Int ?? 250
            try? await HealthKitClient.liveValue.logWater(glassML)
            // Refresh the widget snapshot's water so the hydration ring is
            // up to date even though the app UI may never come up.
            if let total = try? await HealthKitClient.liveValue.todayWaterML() {
                SharedStore.updateWater(intakeML: total)
            }
            WidgetCenter.shared.reloadAllTimelines()
            HydrationNotification.confirm(kind: "drank", amount: glassML)
            // Shift today's reminder grid: next one a full interval from now,
            // not 3 minutes later because a fixed slot was coming up.
            await HydrationReminderScheduler().recordDrinkAndReschedule()
        case HydrationNotification.snoozeAction:
            // "Rappelle-moi" → fire a one-off reminder after the snooze delay.
            let minutes = defaults.object(forKey: "preferences.hydrationSnoozeMinutes") as? Int ?? 15
            try? await NotificationsClient.liveValue.scheduleHydrationSnooze(TimeInterval(minutes * 60))
            HydrationNotification.confirm(kind: "snooze", amount: minutes)
        default:
            break
        }
    }
}
