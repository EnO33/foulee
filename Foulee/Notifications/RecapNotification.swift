import Foundation
import Observation

/// The recap notifications (issue #344): one every Monday for the week that
/// ended, one every 1st for the month that ended. Identifiers and content in
/// one place, read by the client that schedules them and by the delegate that
/// opens the recap on a tap.
///
/// **Fixed text.** A notification is scheduled ahead and cannot read Santé
/// when it fires, so it announces the recap rather than quoting it — the
/// figures are one tap away, and always the current ones.
enum RecapNotification {
    static let prefix = "foulee.recap."
    /// When a recap is announced: 9 h, out of the night and before the day.
    static let hour = 9

    static func identifier(for kind: RecapPeriod.Kind) -> String {
        prefix + kind.rawValue
    }

    /// The recap a notification opens, `nil` for any other notification.
    static func kind(fromIdentifier identifier: String) -> RecapPeriod.Kind? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return RecapPeriod.Kind(rawValue: String(identifier.dropFirst(prefix.count)))
    }

    /// Monday for the week, the 1st for the month, at `hour`.
    static func trigger(for kind: RecapPeriod.Kind) -> DateComponents {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        switch kind {
        case .week: components.weekday = 2 // Calendar numbering: Monday.
        case .month: components.day = 1
        }
        return components
    }

    static func title(for kind: RecapPeriod.Kind) -> String {
        switch kind {
        case .week: "Ta semaine en Foulée"
        case .month: "Ton mois en Foulée"
        }
    }

    static func body(for kind: RecapPeriod.Kind) -> String {
        switch kind {
        case .week: "Ton récap de la semaine est prêt : minutes, pas et objectifs tenus."
        case .month: "Ton récap du mois est prêt : minutes, pas et objectifs tenus."
        }
    }
}

/// Which recap to open, handed from the notification delegate — which runs
/// before any screen may exist — to the home that presents it (issue #344).
@MainActor
@Observable
final class RecapRouter {
    static let shared = RecapRouter()

    private(set) var pending: RecapPeriod.Kind?

    func open(_ kind: RecapPeriod.Kind) {
        pending = kind
    }

    /// Read and clear, so a rebuild of the home does not open it twice.
    func take() -> RecapPeriod.Kind? {
        defer { pending = nil }
        return pending
    }
}
