import SwiftUI

@main
struct FouleeApp: App {
    init() {
        // Handle hydration reminder action taps ("J'ai bu" / "Rappelle-moi"),
        // including when iOS launches the app in the background to do so.
        HydrationNotificationCenter.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
