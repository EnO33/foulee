import Foundation
import Observation
@preconcurrency import WatchConnectivity

/// The wrist's half of carrying a phone walk on (issue #335).
///
/// It learns two things from the phone's application context — that a walk is
/// in progress, and a handoff sent ahead of `startWatchApp` — and it can ask
/// the phone to stop and hand over, for « Reprendre la séance de l'iPhone ».
///
/// A singleton because the context lands in `WatchSyncReceiver`, which has no
/// screen, while the screen that offers the button may not exist yet.
@MainActor
@Observable
final class WatchPhoneHandoff {
    static let shared = WatchPhoneHandoff()

    /// The phone's walk in progress, if it said so.
    private(set) var phoneSession: PhoneSessionStatus?
    /// A request is on its way to the phone.
    private(set) var isRequesting = false
    /// Why the last request did not hand anything over.
    private(set) var errorMessage: String?

    /// A handoff the phone sent ahead of waking this app.
    @ObservationIgnored private var offered: SessionHandoff?
    /// Outings already taken up. The application context is resent whole at
    /// every change, so the same handoff comes back long after it was used.
    @ObservationIgnored private var taken: Set<UUID> = []
    @ObservationIgnored private let requester: PhoneHandoffRequester

    init(requester: PhoneHandoffRequester = .live) {
        self.requester = requester
    }

    /// What the phone's context said. Absent keys mean « nothing »: the phone
    /// sends the whole context every time.
    func receive(phoneSession: PhoneSessionStatus?, handoff: SessionHandoff?) {
        self.phoneSession = phoneSession
        offered = handoff
    }

    /// The handoff to carry on, if the phone sent one recently that nobody has
    /// taken up yet — taking it up. `nil` otherwise: the outing starts fresh.
    func takeOffered(at now: Date) -> SessionHandoff? {
        guard let offered, offered.isFresh(at: now), !taken.contains(offered.outingID) else { return nil }
        take(offered)
        return offered
    }

    /// Ask the phone to stop and hand its walk over.
    ///
    /// `nil` with a message on screen when it does not: the phone is out of
    /// reach, or its walk ended a second before the tap landed.
    func request() async -> SessionHandoff? {
        guard !isRequesting else { return nil }
        isRequesting = true
        errorMessage = nil
        defer { isRequesting = false }
        do {
            guard let handoff = try await requester.request() else {
                phoneSession = nil
                errorMessage = "Aucune séance en cours sur l'iPhone."
                return nil
            }
            take(handoff)
            return handoff
        } catch {
            FouleeLog.session.error(
                "reprise iPhone impossible : \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = "iPhone injoignable. Rapproche-le de ta montre."
            return nil
        }
    }

    private func take(_ handoff: SessionHandoff) {
        taken.insert(handoff.outingID)
        phoneSession = nil
        offered = nil
    }
}

/// Asking the phone for its walk, as one injectable closure (issue #335).
///
/// `WCSession.sendMessage` wakes the iPhone app in the background, so the
/// phone stops and saves its leg without being opened. Nothing about it runs
/// in a simulator — hence the seam.
struct PhoneHandoffRequester: Sendable {
    /// The handoff, `nil` when the phone had no walk to hand over. Throws when
    /// the phone cannot be reached.
    var request: @Sendable () async throws -> SessionHandoff?

    static let live = PhoneHandoffRequester {
        let reply = try await withCheckedThrowingContinuation { continuation in
            WCSession.default.sendMessage(
                [SessionHandoffKey.request: true],
                replyHandler: { reply in
                    continuation.resume(returning: reply[SessionHandoffKey.handoff] as? Data)
                },
                errorHandler: { continuation.resume(throwing: $0) }
            )
        }
        return try reply.map { try JSONDecoder().decode(SessionHandoff.self, from: $0) }
    }
}
