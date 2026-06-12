import SwiftUI

@main
struct FouleeWatchApp: App {
    init() {
        // Start listening for the phone's streak prefs (goal + active days).
        WatchSyncReceiver.shared.activate()
        // Handle "J'ai bu" / "Rappelle-moi" taps on the hydration banner when
        // it's shown on the watch — without this the tap only opens the app.
        WatchHydrationNotificationCenter.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
