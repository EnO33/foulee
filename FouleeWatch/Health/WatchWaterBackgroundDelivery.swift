@preconcurrency import HealthKit
import os
import WidgetKit

/// One-shot guard: `start()` runs on every root-view appearance, and each run
/// would otherwise stack a fresh HKObserverQuery so a single sample fires the
/// handler N times.
private let waterDeliveryStarted = OSAllocatedUnfairLock(initialState: false)

/// Wakes the hydration complication whenever `dietaryWater` changes in Health —
/// including water logged on the iPhone that syncs in while the watch app is
/// closed. Mirrors the phone's `HealthKitClient+BackgroundDelivery`: enable
/// background delivery for water only (rare, so `.immediate` is cheap), then
/// keep a persistent observer that reloads the complication. The today store's
/// own foreground observer handles the in-app card.
enum WatchWaterBackgroundDelivery {
    /// The observer query only lives as long as its store — keep it for the
    /// whole process so deliveries keep landing after the view goes away.
    @MainActor private static var store: HKHealthStore?

    @MainActor
    static func start() async {
        #if DEBUG
        // Capture mode (issue #239): no background delivery, no persistent
        // observer. The seeded intake never changes, and a capture run must
        // leave no registration behind on the simulator it ran on.
        guard !WatchScreenshotMode.isActive else { return }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let shouldStart = waterDeliveryStarted.withLock { started -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard shouldStart else { return }
        let store = HKHealthStore()
        Self.store = store
        let waterType = HKQuantityType(.dietaryWater)
        try? await store.enableBackgroundDelivery(for: waterType, frequency: .immediate)
        let query = HKObserverQuery(sampleType: waterType, predicate: nil) { _, completionHandler, error in
            // watchOS throttles background delivery if the handler isn't
            // called — `defer` guarantees it on every exit.
            defer { completionHandler() }
            guard error == nil else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: WatchComplicationKind.hydration)
        }
        store.execute(query)
    }
}
