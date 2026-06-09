@preconcurrency import WatchConnectivity

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

    private func store(_ context: [String: Any]) {
        guard let data = context["payload"] as? Data,
              let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data) else { return }
        Task { @MainActor in
            WatchSyncStore.write(payload)
            NotificationCenter.default.post(name: .watchSyncReceived, object: nil)
        }
    }
}
