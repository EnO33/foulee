import Dependencies
import Observation
import UserNotifications

/// What iOS lets Foulée do with notifications, in the terms the Réglages page
/// needs (issue #394): ask, point to iOS Settings, or say nothing.
enum NotificationPermission: Equatable {
    /// Not read yet — draws nothing rather than a banner that flickers away.
    case unknown
    case notDetermined
    case denied
    case allowed

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        // Provisional and ephemeral both deliver: nothing to fix.
        case .authorized, .provisional, .ephemeral: self = .allowed
        @unknown default: self = .allowed
        }
    }
}

/// Reads — and on request asks for — the system notification permission,
/// through `NotificationsClient` so the page never touches
/// `UNUserNotificationCenter` itself.
@Observable
final class NotificationPermissionStore {
    private(set) var permission = NotificationPermission.unknown

    @ObservationIgnored @Dependency(\.notifications) private var notifications

    func refresh() async {
        permission = NotificationPermission(await notifications.authorizationStatus())
    }

    /// The system prompt. Shown once by iOS: after a refusal only iOS
    /// Settings can turn notifications back on, hence the `.denied` banner.
    func request() async {
        _ = try? await notifications.requestAuthorization()
        await refresh()
    }
}
