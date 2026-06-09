@preconcurrency import UserNotifications
import WidgetKit

/// Handles taps on the hydration reminder's actions. iOS launches the app in
/// the background to run these, so we read the live prefs and write straight to
/// Health / reschedule — no UI needed. Set as the notification-center delegate
/// once at launch (`FouleeApp.init`).
final class HydrationNotificationCenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = HydrationNotificationCenter()

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show hydration banners even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case HydrationNotification.drankAction:
            // "J'ai bu" → log one glass to Health; the reminder is dismissed
            // by the system automatically.
            let glassML = await MainActor.run { UserPreferences().hydrationGlassML }
            try? await HealthKitClient.liveValue.logWater(glassML)
            WidgetCenter.shared.reloadAllTimelines()
        case HydrationNotification.snoozeAction:
            // "Rappelle-moi" → fire a one-off reminder after the snooze delay.
            let minutes = await MainActor.run { UserPreferences().hydrationSnoozeMinutes }
            try? await NotificationsClient.liveValue.scheduleHydrationSnooze(TimeInterval(minutes * 60))
        default:
            break
        }
    }
}
