import SwiftUI
import WatchKit

@main
struct FouleeWatchApp: App {
    // periphery:ignore - WatchKit reads this through the adaptor; Periphery
    // 3.7.4 only retains the UIKit adaptor, not the watchOS one.
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
        // First, before anything can reach HealthKit: the App Store capture
        // mode (issue #239). Compiled out of Release entirely, and inert
        // without `-FouleeScreenshotMode` on the command line.
        WatchScreenshotMode.activateIfRequested()
        #endif
        // Start listening for the phone's streak prefs (goal + active days).
        WatchSyncReceiver.shared.activate()
        // Handle "J'ai bu" / "Rappelle-moi" taps on the hydration banner when
        // it's shown on the watch — without this the tap only opens the app.
        WatchHydrationNotificationCenter.shared.configure()
        // A workout session that survived a crashed process is picked up by
        // `WatchRootView`, which owns the store (issue #554).
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
