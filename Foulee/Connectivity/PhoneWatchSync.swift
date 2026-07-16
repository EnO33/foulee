import os
@preconcurrency import WatchConnectivity

/// Pushes the streak-relevant prefs (goal + active days) to the Watch via
/// WatchConnectivity application context — latest-state, coalesced, delivered
/// even when the watch app isn't running. iPhone side only.
final class PhoneWatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchSync()

    /// Last payload handed to `send`. Activation is asynchronous, so the first
    /// send of a launch races it — keep the payload and resend once the
    /// session activates (or the watch app gets installed).
    private let pendingPayload = OSAllocatedUnfairLock<WatchSyncPayload?>(initialState: nil)

    override private init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ payload: WatchSyncPayload) {
        pendingPayload.withLock { $0 = payload }
        pushPendingPayloadIfPossible()
    }

    /// Whether `updateApplicationContext` can succeed right now. Pure so the
    /// gating is unit-testable without a `WCSession`.
    static func canPush(activationState: WCSessionActivationState, isWatchAppInstalled: Bool) -> Bool {
        activationState == .activated && isWatchAppInstalled
    }

    private func pushPendingPayloadIfPossible() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard Self.canPush(
            activationState: session.activationState,
            isWatchAppInstalled: session.isWatchAppInstalled
        ),
            let payload = pendingPayload.withLock({ $0 }),
            let data = try? JSONEncoder().encode(payload) else { return }
        try? session.updateApplicationContext(["payload": data])
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        pushPendingPayloadIfPossible()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        // Fires when `isWatchAppInstalled` flips — resend so installing the
        // watch app after the fact syncs without reopening the iPhone app.
        pushPendingPayloadIfPossible()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
