import AppIntents

// periphery:ignore - discovered by the AppIntents runtime at install, never referenced from code.
/// Exposes "J'ai bu un verre" and « Où j'en suis aujourd'hui » to Raccourcis,
/// Spotlight, Siri and the Action button — the system registers these phrases
/// automatically at install.
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
        AppShortcut(
            intent: TodayStatusIntent(),
            phrases: [
                "Où j'en suis dans \(.applicationName)",
                "Où j'en suis aujourd'hui avec \(.applicationName)",
                "Ma série \(.applicationName)"
            ],
            shortTitle: "Où j'en suis aujourd'hui",
            systemImageName: "flame.fill"
        )
    }
}
