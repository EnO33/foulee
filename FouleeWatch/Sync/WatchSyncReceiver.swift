@preconcurrency import WatchConnectivity
import WidgetKit

extension Notification.Name {
    /// Posted (on the main actor) when fresh prefs arrive from the phone.
    static let watchSyncReceived = Notification.Name("watchSyncReceived")
}

/// Receives the phone's streak prefs and persists them so the watch computes
/// the same streak. Activate once at app launch.
final class WatchSyncReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSyncReceiver()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Pick up the latest context already queued at activation.
        store(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        store(applicationContext)
    }

    /// A live state of the phone's session (issue #342).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[PhoneSessionKey.snapshot] as? Data,
              let snapshot = try? JSONDecoder().decode(PhoneSessionSnapshot.self, from: data) else { return }
        Task { @MainActor in WatchPhoneSession.shared.receive(snapshot) }
    }

    private func store(_ context: [String: Any]) {
        receivePhoneSession(context)
        guard let data = context["payload"] as? Data,
              let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data) else { return }
        Task { @MainActor in
            WatchSyncStore.write(payload)
            NotificationCenter.default.post(name: .watchSyncReceived, object: nil)
            // Refresh the Série complication with the new goal / active days.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The phone's session from the context (issue #342). Read on every
    /// context, key present or not: the phone resends the whole context at
    /// each change, so an absent key is the phone saying « no session ».
    private func receivePhoneSession(_ context: [String: Any]) {
        let snapshot = (context[PhoneSessionKey.snapshot] as? Data)
            .flatMap { try? JSONDecoder().decode(PhoneSessionSnapshot.self, from: $0) }
        Task { @MainActor in WatchPhoneSession.shared.receive(snapshot) }
    }
}
