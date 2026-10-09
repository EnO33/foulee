import os
@preconcurrency import WatchConnectivity

/// Pushes the streak-relevant prefs (goal + active days) to the Watch via
/// WatchConnectivity application context — latest-state, coalesced, delivered
/// even when the watch app isn't running. iPhone side only.
///
/// Since issue #335 the context also carries the phone's walk in progress and
/// a handoff to the wrist, and this is where the wrist's « stop and hand
/// over » request lands.
final class PhoneWatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchSync()

    /// Everything the context carries. One value, because
    /// `updateApplicationContext` **replaces** the whole dictionary: sending
    /// the walk's state alone would wipe the synced prefs off the wrist.
    struct Context: Sendable {
        var payload: WatchSyncPayload?
        var phoneSession: PhoneSessionStatus?
        var handoff: SessionHandoff?

        /// The dictionary as WatchConnectivity wants it. Pure, so what reaches
        /// the wrist is asserted without a `WCSession`.
        var dictionary: [String: Any] {
            let encoder = JSONEncoder()
            var context: [String: Any] = [:]
            context["payload"] = payload.flatMap { try? encoder.encode($0) }
            context[SessionHandoffKey.phoneSession] = phoneSession.flatMap { try? encoder.encode($0) }
            context[SessionHandoffKey.handoff] = handoff.flatMap { try? encoder.encode($0) }
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

    /// The phone's walk in progress, or `nil` once it is over (issue #335).
    func publish(phoneSession: PhoneSessionStatus?) {
        update { $0.phoneSession = phoneSession }
    }

    /// The phone stopped so the wrist can carry on (issue #335). Kept in the
    /// context rather than sent as a message: the watch app is being woken by
    /// `startWatchApp` at this very moment and is not reachable yet, while the
    /// context is waiting for it whenever it starts listening.
    func publish(handoff: SessionHandoff) {
        update { $0.handoff = handoff }
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

    /// The wrist asks to carry on the walk in progress (issue #335).
    ///
    /// Delivered even with the app in the background — iOS wakes it for a
    /// message from the watch — so the phone stops and saves its leg without
    /// being opened. The reply is the handoff, or empty when there is no walk
    /// to hand over: the phone stopped a second before the tap landed.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let reply = UncheckedSendableBox(replyHandler)
        guard message[SessionHandoffKey.request] != nil else {
            reply.value([:])
            return
        }
        Task { @MainActor in
            let handoff = await ActiveWalkStore.current?.handOff()
            let data = handoff.flatMap { try? JSONEncoder().encode($0) }
            FouleeLog.session.notice(
                "reprise demandée par la Watch : \(data == nil ? "aucune séance" : "transmise", privacy: .public)"
            )
            reply.value(data.map { [SessionHandoffKey.handoff: $0] } ?? [:])
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
