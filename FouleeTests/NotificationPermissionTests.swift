import Dependencies
import Testing
import UserNotifications
@testable import Foulee

/// The Réglages notifications page reads what iOS allows (issue #394).
@Suite("Notification permission")
@MainActor
struct NotificationPermissionTests {
    @Test("Every system status maps to what the page must show", arguments: [
        (UNAuthorizationStatus.notDetermined, NotificationPermission.notDetermined),
        (.denied, .denied),
        (.authorized, .allowed),
        (.provisional, .allowed),
        (.ephemeral, .allowed)
    ] as [(UNAuthorizationStatus, NotificationPermission)])
    func mapping(status: UNAuthorizationStatus, expected: NotificationPermission) {
        #expect(NotificationPermission(status) == expected)
    }

    @Test("Nothing is shown before the status is read")
    func startsUnknown() {
        #expect(NotificationPermissionStore().permission == .unknown)
    }

    @Test("A refresh reads the system status")
    func refresh() async {
        await withDependencies {
            $0.notifications.authorizationStatus = { .denied }
        } operation: {
            let store = NotificationPermissionStore()
            await store.refresh()
            #expect(store.permission == .denied)
        }
    }

    @Test("Asking re-reads the status the prompt left")
    func request() async {
        await withDependencies {
            $0.notifications.requestAuthorization = { true }
            $0.notifications.authorizationStatus = { .authorized }
        } operation: {
            let store = NotificationPermissionStore()
            await store.request()
            #expect(store.permission == .allowed)
        }
    }
}
