import AppIntents
@preconcurrency import HealthKit

/// « J'ai bu un verre » for Siri on the watch (issue #607). The phone's intent
/// of the same name writes to the phone's Santé; this one writes to the
/// watch's, without opening the app, through the hydration banner's own path.
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource { "J'ai bu un verre" }
    // periphery:ignore - read by the AppIntents runtime, never from code.
    static var description: IntentDescription { "Enregistre un verre d'eau dans Santé." }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog: IntentDialog = switch await WatchWaterLog.logGlass(store: HKHealthStore()) {
        case .logged(let glassML):
            "C'est noté : +\(glassML) ml d'eau."
        case .unavailable:
            "Santé n'est pas disponible sur cet appareil."
        case .denied:
            "Foulée n'a pas l'autorisation d'écrire dans Santé. Active l'eau dans Santé > Profil > Apps > Foulée."
        case .notDetermined:
            "Ouvre d'abord Foulée pour autoriser l'accès à Santé."
        case .failed:
            "Verre non enregistré — réessaie"
        }
        return .result(dialog: dialog)
    }
}
