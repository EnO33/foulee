import FouleeKit
import Foundation
import Observation

/// The recap notifications (issues #344, #350, #363): one every Sunday evening
/// for the week that ends, one every 1st for the month that ended. Identifiers
/// and content in one place, read by the client that schedules them and by
/// the delegate that opens the recap on a tap.
///
/// **Fixed text.** A notification is scheduled ahead and cannot read Santé
/// when it fires, so it announces the recap rather than quoting it — the
/// figures are one tap away, and always the current ones.
nonisolated enum RecapNotification {
    static let prefix = "foulee.recap."

    static func identifier(for kind: RecapPeriod.Kind) -> String {
        prefix + kind.rawValue
    }

    /// The recap a notification opens, `nil` for any other notification.
    static func kind(fromIdentifier identifier: String) -> RecapPeriod.Kind? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return RecapPeriod.Kind(rawValue: String(identifier.dropFirst(prefix.count)))
    }

    /// Sunday at 19 h for the week: the Bilan's week is the one in progress
    /// (#363), whole only on a Sunday, once the day is mostly behind. The 1st
    /// at 9 h for the month, which has ended.
    static func trigger(for kind: RecapPeriod.Kind) -> DateComponents {
        var components = DateComponents()
        components.minute = 0
        switch kind {
        case .week:
            components.weekday = 1 // Calendar numbering: Sunday.
            components.hour = 19
        case .month:
            components.day = 1
            components.hour = 9
        }
        return components
    }

    static func title(for kind: RecapPeriod.Kind) -> String {
        switch kind {
        case .week: "Ta semaine en Foulée"
        case .month: "Ton mois en Foulée"
        }
    }

    /// What a tap opens (issue #444). Sunday evening, the week in progress,
    /// almost whole. The 1st, the month that just ended: the month in
    /// progress is a day old and says nothing yet.
    static func request(for kind: RecapPeriod.Kind) -> RecapRequest {
        RecapRequest(kind: kind, lastCompleted: kind == .month)
    }

    static func body(for kind: RecapPeriod.Kind) -> String {
        switch kind {
        case .week: "Ton récap de la semaine est prêt : minutes, pas et objectifs tenus."
        case .month: "Ton récap du mois est prêt : minutes, pas et objectifs tenus."
        }
    }
}

/// A recap to open (issue #444): its kind, and whether on the period in
/// progress or the last finished one — or on the outing a session
/// notification announced (issue #530).
nonisolated struct RecapRequest: Hashable, Identifiable {
    let kind: RecapPeriod.Kind
    var lastCompleted = false
    /// The outing to open, pushed once the Bilan has read it.
    var outing: DateInterval?

    var id: Self { self }

    /// The page to open on, `nil` for the period in progress.
    func period(at now: Date) -> RecapPeriod? {
        if let outing {
            let current = RecapPeriod.current(kind, at: now)
            return current.contains(outing.start) ? nil : RecapPeriod.containing(outing.start, kind)
        }
        return lastCompleted ? RecapPeriod.lastCompleted(kind, before: now) : nil
    }
}

/// Which recap to open, handed from the notification delegate — which runs
/// before any screen may exist — to the home that presents it (issue #344).
@Observable
final class RecapRouter {
    static let shared = RecapRouter()

    private(set) var pending: RecapRequest?

    func open(_ kind: RecapPeriod.Kind) {
        open(RecapRequest(kind: kind))
    }

    func open(_ request: RecapRequest) {
        pending = request
    }

    /// Read and clear, so a rebuild of the home does not open it twice.
    func take() -> RecapRequest? {
        defer { pending = nil }
        return pending
    }
}
