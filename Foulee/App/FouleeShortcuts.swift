import AppIntents

// periphery:ignore - discovered by the AppIntents runtime at install, never referenced from code.
/// Exposes "J'ai bu un verre" to Raccourcis, Spotlight, Siri and the Action
/// button — the system registers these phrases automatically at install.
struct FouleeShortcuts: AppShortcutsProvider {
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
    }
}
