import Dependencies
import Foundation

/// The phone's session as the wrist is told of it (issue #342), as an
/// injectable struct-of-closures.
///
/// Fire-and-forget on purpose: nothing on the phone waits for the wrist — a
/// walk is never held up by a watch that is off, unpaired or out of range.
struct WatchLiveClient: Sendable {
    /// The session's latest state, or `nil` once there is none.
    var publish: @Sendable (PhoneSessionSnapshot?) -> Void
}

extension WatchLiveClient: DependencyKey {
    static let liveValue = WatchLiveClient { PhoneWatchSync.shared.publish(session: $0) }
    static let previewValue = WatchLiveClient { _ in }
    static let testValue = previewValue
}

extension DependencyValues {
    var watchLive: WatchLiveClient {
        get { self[WatchLiveClient.self] }
        set { self[WatchLiveClient.self] = newValue }
    }
}
