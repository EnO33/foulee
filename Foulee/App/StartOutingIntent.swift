import AppIntents
import FouleeKit
import Observation

/// « Commencer une sortie » for Siri, Raccourcis and Spotlight (issue #604).
/// Opens Foulée and starts the outing the way the home button does: the
/// intent only hands the request to the home, which owns the session.
struct StartOutingIntent: AppIntent {
    static var title: LocalizedStringResource { "Commencer une sortie" }
    // periphery:ignore - read by the AppIntents runtime, never from code.
    static var description: IntentDescription { "Ouvre Foulée et démarre une sortie." }
    // periphery:ignore - read by the AppIntents runtime, never from code.
    static var supportedModes: IntentModes { .foreground }

    /// Left empty, the user's own mode decides, as on the home button.
    @Parameter(title: "Sport")
    var activity: OutingActivity?

    @MainActor
    func perform() async throws -> some IntentResult {
        SessionStartRouter.shared.start(activity?.mode)
        return .result()
    }
}

/// The sport as Raccourcis lists it and Siri hears it.
nonisolated enum OutingActivity: String, AppEnum {
    case walking
    case running
    case automatic

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Sport" }

    static var caseDisplayRepresentations: [OutingActivity: DisplayRepresentation] {
        [
            .walking: DisplayRepresentation(title: "Marche"),
            .running: DisplayRepresentation(title: "Course"),
            .automatic: DisplayRepresentation(
                title: "Automatique",
                subtitle: "Foulée reconnaît la marche ou la course"
            )
        ]
    }

    /// « Automatique » is « les deux »: the session's own motion history
    /// settles the sport at the end (#246).
    var mode: ActivityMode {
        switch self {
        case .walking: .walking
        case .running: .running
        case .automatic: .both
        }
    }
}

/// A start asked for by a shortcut, carried to the home that presents the
/// session — the intent runs before any screen may be mounted.
nonisolated struct SessionStartRequest: Equatable {
    /// `nil` when the shortcut named no sport: the user's own mode decides.
    let mode: ActivityMode?
}

@Observable
final class SessionStartRouter {
    static let shared = SessionStartRouter()

    private(set) var pending: SessionStartRequest?

    func start(_ mode: ActivityMode?) {
        pending = SessionStartRequest(mode: mode)
    }

    /// Read and clear, so a rebuild of the home does not start twice.
    func take() -> SessionStartRequest? {
        guard let request = pending else { return nil }
        pending = nil
        return request
    }
}
