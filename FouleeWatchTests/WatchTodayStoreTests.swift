import Foundation
import Testing
@testable import FouleeWatch

@MainActor
@Suite("WatchTodayStore")
struct WatchTodayStoreTests {
    /// The store's signal observers hop to the main actor through a `Task` —
    /// yield until the assignment lands (bounded so a regression fails the
    /// assertion instead of hanging the test).
    private func settle(until landed: () -> Bool) async {
        for _ in 0..<1_000 where !landed() {
            await Task.yield()
        }
    }

    @Test("Init starts with no hydration error and no denial")
    func initIsInert() {
        let store = WatchTodayStore()
        #expect(store.hydrationError == nil)
        #expect(!store.waterDenied)
    }

    @Test("A failed save signalled by the notification action reaches the card")
    func failureSignalSetsHydrationError() async {
        let store = WatchTodayStore()
        NotificationCenter.default.post(name: .watchHydrationActionFailed, object: nil)
        await settle { store.hydrationError != nil }
        #expect(store.hydrationError == "Verre non enregistré — réessaie")
    }

    @Test("A denial signalled by the notification action reaches the card")
    func denialSignalSetsWaterDenied() async {
        let store = WatchTodayStore()
        NotificationCenter.default.post(name: .watchHydrationActionDenied, object: nil)
        await settle { store.waterDenied }
        #expect(store.waterDenied)
    }
}
