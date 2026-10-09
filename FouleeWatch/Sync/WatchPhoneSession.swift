import Foundation
import Observation
@preconcurrency import WatchConnectivity

/// The phone's session in flight, as the wrist shows it (issue #342).
///
/// Fed by `WatchSyncReceiver` — live messages while the phone is reachable,
/// the application context otherwise — and able to send the phone a command.
/// A singleton because the state lands in the receiver, which has no screen,
/// while the screen that shows it may not exist yet.
@MainActor
@Observable
final class WatchPhoneSession {
    static let shared = WatchPhoneSession()

    /// Past this without news, a session is taken for gone: the phone app was
    /// killed, or the phone left with its owner. A session in flight is
    /// retold every few seconds while the phone can reach the wrist.
    static let staleAfter: TimeInterval = 15 * 60

    /// The newest state the phone sent, whatever its age.
    private(set) var snapshot: PhoneSessionSnapshot?
    /// A command is on its way to the phone.
    private(set) var isSending = false
    /// Why the last command was not carried out.
    private(set) var errorMessage: String?

    @ObservationIgnored private let sender: PhoneCommandSender

    init(sender: PhoneCommandSender = .live) {
        self.sender = sender
    }

    /// What the phone said. Newest wins: a context and a live message can
    /// carry the same session in either order. `nil` — no session — always
    /// wins, so a session the phone let go of never lingers here.
    func receive(_ snapshot: PhoneSessionSnapshot?) {
        guard let snapshot else {
            self.snapshot = nil
            return
        }
        if let current = self.snapshot, current.sentAt > snapshot.sentAt { return }
        self.snapshot = snapshot
    }

    /// The session to show, if any: not ended, and not gone stale.
    func shown(at now: Date) -> PhoneSessionSnapshot? {
        guard let snapshot, snapshot.phase != .ended,
              now.timeIntervalSince(snapshot.sentAt) <= Self.staleAfter
        else { return nil }
        return snapshot
    }

    /// Ask the phone to pause, resume or stop. The screen changes when the
    /// phone says the session did, not when the button is tapped.
    func send(_ command: PhoneSessionCommand) async {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            if try await sender.send(command) == false {
                errorMessage = "La séance de l'iPhone est déjà terminée."
            }
        } catch {
            FouleeLog.session.error(
                "commande iPhone impossible : \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = "iPhone injoignable. Rapproche-le de ta montre."
        }
    }
}

/// Sending the phone a command, as one injectable closure (issue #342).
///
/// `WCSession.sendMessage` wakes the iPhone app in the background. Nothing
/// about it runs in a simulator — hence the seam.
struct PhoneCommandSender: Sendable {
    /// Whether the phone carried the command out. Throws when it cannot be
    /// reached.
    var send: @Sendable (PhoneSessionCommand) async throws -> Bool

    static let live = PhoneCommandSender { command in
        try await withCheckedThrowingContinuation { continuation in
            WCSession.default.sendMessage(
                [PhoneSessionKey.command: command.rawValue],
                replyHandler: { reply in
                    continuation.resume(returning: reply[PhoneSessionKey.done] as? Bool ?? false)
                },
                errorHandler: { continuation.resume(throwing: $0) }
            )
        }
    }
}
