import Dependencies
import Foundation

/// What the phone tells the wrist about its own walk (issue #335), as an
/// injectable struct-of-closures.
///
/// Fire-and-forget on purpose: both ride WatchConnectivity's application
/// context, which delivers the latest state whenever the watch next listens.
/// Nothing on the phone waits for the wrist — a walk is never held up by a
/// watch that is off, unpaired or out of range.
struct WatchHandoffClient: Sendable {
    /// The walk in progress, or `nil` once it is over. Lets the wrist offer
    /// « Reprendre la séance de l'iPhone ».
    var publishPhoneSession: @Sendable (PhoneSessionStatus?) -> Void
    /// The phone stopped so the wrist can carry on: what it measured, for the
    /// watch to take up as the outing's first leg.
    var publishHandoff: @Sendable (SessionHandoff) -> Void
}

extension WatchHandoffClient: DependencyKey {
    static let liveValue = WatchHandoffClient(
        publishPhoneSession: { PhoneWatchSync.shared.publish(phoneSession: $0) },
        publishHandoff: { PhoneWatchSync.shared.publish(handoff: $0) }
    )

    static let previewValue = WatchHandoffClient(
        publishPhoneSession: { _ in },
        publishHandoff: { _ in }
    )

    static let testValue = previewValue
}

extension DependencyValues {
    var watchHandoff: WatchHandoffClient {
        get { self[WatchHandoffClient.self] }
        set { self[WatchHandoffClient.self] = newValue }
    }
}
