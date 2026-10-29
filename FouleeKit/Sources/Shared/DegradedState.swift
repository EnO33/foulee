import Foundation

/// What iOS lets Foulée do with one capability, in the terms a message needs.
///
/// Plain cases rather than a system status, so the decisions below stay
/// testable on macOS: `CLAuthorizationStatus.access` and the motion client
/// convert to it.
nonisolated public enum Access: Equatable, Sendable {
    /// Not read yet: draws nothing rather than a message that flickers away.
    case unknown
    case notDetermined
    case denied
    case granted
}

/// Something Foulée cannot do right now, told in one message with the one
/// action that fixes it (issue #611).
///
/// Each case says what is missing for the user, not which API failed: « pas de
/// tracé » means more than « localisation refusée ».
nonisolated public enum DegradedState: Hashable, Sendable, CaseIterable {
    /// A Santé read failed. HealthKit never says a read was refused, so this
    /// is the closest the app gets to « Santé refusée ».
    case healthUnreadable
    /// Writing water was refused: « J'ai bu » cannot count a glass.
    case waterWriteDenied
    case locationDenied
    case motionDenied
    /// The location is allowed but WeatherKit did not answer.
    case weatherUnavailable
    /// Santé holds nothing for the period shown.
    case noData

    /// Where the fix lives.
    public enum Remedy: Equatable, Sendable {
        /// Santé > Profil > Apps > Foulée: the only place HealthKit grants change.
        case openHealth
        /// Foulée's page in iOS Settings, where location and motion change.
        case openSettings

        /// The button's label.
        public var title: String {
            switch self {
            case .openHealth: kitText("Ouvrir Santé")
            case .openSettings: kitText("Ouvrir les réglages")
            }
        }
    }

    /// `nil` when nothing the user does fixes it: waiting is the only answer.
    public var remedy: Remedy? {
        switch self {
        case .healthUnreadable, .waterWriteDenied, .noData: .openHealth
        case .locationDenied, .motionDenied: .openSettings
        case .weatherUnavailable: nil
        }
    }

    public var title: String {
        switch self {
        case .healthUnreadable: kitText("Données partiellement indisponibles")
        case .waterWriteDenied: kitText("Eau non autorisée")
        case .locationDenied: kitText("Localisation refusée")
        case .motionDenied: kitText("Mouvements refusés")
        case .weatherUnavailable: kitText("Météo indisponible")
        case .noData: kitText("Pas encore de données")
        }
    }

    /// What the app cannot do, then how to fix it.
    public var message: String {
        switch self {
        case .healthUnreadable:
            kitText("Certains chiffres peuvent manquer. Vérifie l'accès de Foulée dans Santé, puis réessaie.")
        case .waterWriteDenied:
            kitText("Foulée ne peut pas compter tes verres. Autorise l'eau dans Santé.")
        case .locationDenied:
            kitText("Pas de météo locale ni de tracé de tes sorties. Autorise la localisation dans Réglages.")
        case .motionDenied:
            kitText("Pas de pas en direct pendant une sortie, ni de tri marche ou course. Autorise « Mouvements et forme » dans Réglages.")
        case .weatherUnavailable:
            kitText("La météo n'a pas répondu. Réessaie dans un moment.")
        case .noData:
            kitText("Rien n'est enregistré dans Santé sur cette période. Vérifie que Foulée peut lire tes données dans Santé.")
        }
    }
}

nonisolated public extension DegradedState {
    /// The refused permissions, most limiting first: what the Réglages page
    /// lists. Health reads are not among them: HealthKit never tells.
    /// An outing leaves `waterWriteDenied` out: it has nothing to do with a glass.
    static func permissions(location: Access, motion: Access, waterWriteDenied: Bool = false) -> [DegradedState] {
        var states: [DegradedState] = []
        if location == .denied { states.append(.locationDenied) }
        if motion == .denied { states.append(.motionDenied) }
        if waterWriteDenied { states.append(.waterWriteDenied) }
        return states
    }

    /// Why the forecast is missing. A refused location outranks WeatherKit:
    /// without a position there was nothing to ask it.
    static func weather(location: Access) -> DegradedState {
        location == .denied ? .locationDenied : .weatherUnavailable
    }
}
