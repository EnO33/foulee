import os
@preconcurrency import WatchConnectivity

/// Pushes the streak-relevant prefs (goal + active days) to the Watch via
/// WatchConnectivity application context — latest-state, coalesced, delivered
/// even when the watch app isn't running. iPhone side only.
///
/// Since issue #342 it also carries the phone's session in flight to the
/// wrist, and runs the commands the wrist sends back.
final class PhoneWatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchSync()

    /// Everything the context carries. One value, because
    /// `updateApplicationContext` **replaces** the whole dictionary: sending
    /// the session alone would wipe the synced prefs off the wrist.
    struct Context: Sendable {
        var payload: WatchSyncPayload?
        var session: PhoneSessionSnapshot?

        /// The dictionary as WatchConnectivity wants it. Pure, so what reaches
        /// the wrist is asserted without a `WCSession`.
        var dictionary: [String: Any] {
            let encoder = JSONEncoder()
            var context: [String: Any] = [:]
            context["payload"] = payload.flatMap { try? encoder.encode($0) }
            context[PhoneSessionKey.snapshot] = session.flatMap { try? encoder.encode($0) }
            return context
        }
    }

    /// The last state handed in. Activation is asynchronous, so the first send
    /// of a launch races it — keep it and resend once the session activates
    /// (or the watch app gets installed).
    private let pending = OSAllocatedUnfairLock(initialState: Context())

    #if DEBUG
    /// Set by the screenshot capture mode, whose streak is fabricated and has
    /// no business reaching a paired Watch. Muted here rather than at the call
    /// site so nothing is kept pending either: activation and a watch-app
    /// install both resend, and a payload never stored can't be resent.
    ///
    /// `nonisolated(unsafe)`: assigned once, from `FouleeApp.init()`, before
    /// any send. Debug-only — a Release build cannot mute this.
    nonisolated(unsafe) static var isMuted = false
    #endif

    override private init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ payload: WatchSyncPayload) {
        update { $0.payload = payload }
    }

    /// The phone's session in flight, or `nil` once there is none (#342).
    ///
    /// Twice: live to a wrist that is listening right now, and in the context
    /// for one that opens the app later — the context alone arrives when
    /// WatchConnectivity sees fit, which is no clock to run a session on.
    /// « No session » travels in the context only: an ended session has
    /// already been said live.
    func publish(session snapshot: PhoneSessionSnapshot?) {
        #if DEBUG
        guard !Self.isMuted else { return }
        #endif
        update { $0.session = snapshot }
        guard let snapshot, WCSession.isSupported(), WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        WCSession.default.sendMessage([PhoneSessionKey.snapshot: data], replyHandler: nil) { error in
            FouleeLog.session.notice(
                "séance non transmise en direct : \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func update(_ change: @Sendable (inout Context) -> Void) {
        #if DEBUG
        guard !Self.isMuted else { return }
        #endif
        pending.withLock { change(&$0) }
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
        ) else { return }
        let context = pending.withLock { $0 }.dictionary
        guard !context.isEmpty else { return }
        do {
            try session.updateApplicationContext(context)
        } catch {
            FouleeLog.session.error(
                "contexte Watch non transmis : \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// A command from the wrist (issue #342).
    ///
    /// Delivered even with the app in the background — iOS wakes it for a
    /// message from the watch. The reply says whether a session was there to
    /// obey.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let reply = UncheckedSendableBox(replyHandler)
        guard let raw = message[PhoneSessionKey.command] as? String,
              let command = PhoneSessionCommand(rawValue: raw) else {
            reply.value([PhoneSessionKey.done: false])
            return
        }
        Task { @MainActor in
            let done = await ActiveWalkStore.current?.perform(command) ?? false
            FouleeLog.session.notice(
                "commande Watch \(raw, privacy: .public) : \(done ? "exécutée" : "sans séance", privacy: .public)"
            )
            reply.value([PhoneSessionKey.done: done])
        }
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
