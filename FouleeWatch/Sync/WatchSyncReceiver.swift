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

    private func store(_ context: [String: Any]) {
        receiveHandoff(context)
        guard let data = context["payload"] as? Data,
              let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data) else { return }
        Task { @MainActor in
            WatchSyncStore.write(payload)
            NotificationCenter.default.post(name: .watchSyncReceived, object: nil)
            // Refresh the Série complication with the new goal / active days.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The phone's walk and handoff (issue #335). Read on every context, keys
    /// present or not: the phone resends the whole context at each change, so
    /// an absent key is the phone saying « none ».
    private func receiveHandoff(_ context: [String: Any]) {
        let decoder = JSONDecoder()
        let phoneSession = (context[SessionHandoffKey.phoneSession] as? Data)
            .flatMap { try? decoder.decode(PhoneSessionStatus.self, from: $0) }
        let handoff = (context[SessionHandoffKey.handoff] as? Data)
            .flatMap { try? decoder.decode(SessionHandoff.self, from: $0) }
        Task { @MainActor in
            WatchPhoneHandoff.shared.receive(phoneSession: phoneSession, handoff: handoff)
        }
    }
}
