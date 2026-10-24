import FouleeKit
import Foundation

/// What a session notification carries, and what its tap opens (issue #530):
/// the Bilan of the outing's week, pushed to the outing itself.
nonisolated enum SessionNotification {
    private static let startedAtKey = "startedAt"
    private static let endedAtKey = "endedAt"

    /// The outing's clock, as plain numbers: all `userInfo` keeps.
    static func userInfo(for notice: SessionNotice) -> [String: Double] {
        [
            startedAtKey: notice.startedAt.timeIntervalSince1970,
            endedAtKey: notice.endedAt.timeIntervalSince1970
        ]
    }

    /// The Bilan a session notification opens, `nil` for any other
    /// notification.
    static func request(identifier: String, userInfo: [AnyHashable: Any]) -> RecapRequest? {
        guard identifier.hasPrefix(SessionNotice.prefix),
              let start = userInfo[startedAtKey] as? Double,
              let end = userInfo[endedAtKey] as? Double,
              end >= start else { return nil }
        let outing = DateInterval(
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end)
        )
        return RecapRequest(kind: .week, outing: outing)
    }
}
