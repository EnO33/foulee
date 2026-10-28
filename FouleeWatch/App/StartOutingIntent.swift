import AppIntents
import FouleeKit

/// « Commencer une sortie » for Siri on the watch (issue #607). The phone's
/// intent of the same name, minus « Automatique »: the watch writes its own
/// workout, and a sport nobody chose would stamp Santé for good (#223).
///
/// Left empty, it does what « Démarrer » does: the synced mode starts its
/// sport, and « les deux » asks on the wrist. The intent only parks the
/// request; `WatchRootView` owns the session.
struct StartOutingIntent: AppIntent {
    static var title: LocalizedStringResource { "Commencer une sortie" }
    // periphery:ignore - read by the AppIntents runtime, never from code.
    static var description: IntentDescription { "Ouvre Foulée et démarre une sortie." }
    // periphery:ignore - read by the AppIntents runtime, never from code.
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Sport")
    var activity: WatchOutingActivity?

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchPendingStart.shared.request(Self.startIntent(for: activity))
        return .result()
    }

    /// Static so a test drives it against a throwaway defaults suite, like
    /// `WatchRootView.startIntent`.
    @MainActor
    static func startIntent(
        for activity: WatchOutingActivity?,
        syncedTo defaults: UserDefaults = WatchSyncStore.sharedDefaults
    ) -> ActivityStartIntent {
        activity.map { ActivityStartIntent.start($0.activity) } ?? WatchRootView.startIntent(syncedTo: defaults)
    }
}

/// The Action button of the Apple Watch Ultra (issue #607). Its settings list
/// `suggestedWorkouts`, one per sport, and the wearer picks one once: the
/// protocol wants a sport, so there is no « follow my mode » here.
struct StartWorkoutOutingIntent: StartWorkoutIntent {
    static var title: LocalizedStringResource { "Commencer une sortie" }
    // periphery:ignore - read by the AppIntents runtime, never from code.
    /// Hidden from Raccourcis, which already lists `StartOutingIntent`.
    static var isDiscoverable: Bool { false }

    // periphery:ignore - read by the AppIntents runtime, never from code.
    static var suggestedWorkouts: [StartWorkoutOutingIntent] {
        WatchOutingActivity.allCases.map { StartWorkoutOutingIntent(style: $0) }
    }

    @Parameter(title: "Sport")
    var workoutStyle: WatchOutingActivity

    // periphery:ignore - read by the AppIntents runtime, never from code.
    var displayRepresentation: DisplayRepresentation {
        WatchOutingActivity.caseDisplayRepresentations[workoutStyle]
            ?? DisplayRepresentation(title: "Sortie")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchPendingStart.shared.request(.start(workoutStyle.activity))
        return .result()
    }
}

/// The sport as Siri hears it and the Action button lists it.
enum WatchOutingActivity: String, AppEnum, CaseIterable {
    case walking
    case running

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Sport" }

    static var caseDisplayRepresentations: [WatchOutingActivity: DisplayRepresentation] {
        [
            .walking: DisplayRepresentation(title: "Marche", image: .init(systemName: "figure.walk")),
            .running: DisplayRepresentation(title: "Course", image: .init(systemName: "figure.run"))
        ]
    }

    var activity: SessionActivity {
        switch self {
        case .walking: .walking
        case .running: .running
        }
    }
}
