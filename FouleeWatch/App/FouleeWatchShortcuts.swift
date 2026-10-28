import AppIntents

// periphery:ignore - discovered by the AppIntents runtime at install, never referenced from code.
/// The phone's `FouleeShortcuts`, on the wrist (issue #607): « J'ai bu un
/// verre » and « Commencer une sortie » for Siri on the watch, with the same
/// phrases. The Action button reads `StartWorkoutOutingIntent` instead.
struct FouleeWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "J'ai bu un verre dans \(.applicationName)",
                "Ajoute un verre d'eau dans \(.applicationName)"
            ],
            shortTitle: "J'ai bu un verre",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: StartOutingIntent(),
            phrases: [
                "Commence une sortie avec \(.applicationName)",
                "Commence une \(\.$activity) avec \(.applicationName)",
                "Démarre une \(\.$activity) avec \(.applicationName)"
            ],
            shortTitle: "Commencer une sortie",
            systemImageName: "figure.walk"
        )
    }
}
