import SwiftUI

@main
struct FouleeWatchApp: App {
    init() {
        // Start listening for the phone's streak prefs (goal + active days).
        WatchSyncReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
