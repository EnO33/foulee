import FouleeKit
@preconcurrency import HealthKit
import WidgetKit

/// One glass of water, logged from outside the home screen: the hydration
/// banner's « J'ai bu » (`WatchHydrationNotificationCenter`) and Siri's
/// « J'ai bu un verre » (`LogWaterIntent`, issue #607). Both run without
/// `WatchTodayStore`, which owns the card, so both tell it through the same
/// signals.
enum WatchWaterLog {
    enum Outcome: Equatable {
        case logged(milliliters: Int)
        case unavailable
        case denied
        /// Never answered: only the app, on screen, can show the question.
        case notDetermined
        case failed
    }

    /// Log the phone-synced glass to the watch's HealthKit, then nudge the
    /// home to re-read so the card and haptic reflect it. A denied
    /// authorization or a failed save posts the matching failure signal
    /// instead — the glass didn't count, and only `WatchTodayStore` can say so
    /// on the card.
    static func logGlass(store: HKHealthStore) async -> Outcome {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        let waterType = HKQuantityType(.dietaryWater)
        _ = try? await store.requestAuthorization(toShare: [waterType], read: [waterType])
        switch store.authorizationStatus(for: waterType) {
        case .sharingDenied:
            await post(.watchHydrationActionDenied)
            return .denied
        case .notDetermined:
            await post(.watchHydrationActionFailed)
            return .notDetermined
        default:
            break
        }
        let glassML = WatchSyncStore.read()?.hydrationGlassML ?? 250
        let sample = HKQuantitySample(
            type: waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(glassML)),
            start: .now,
            end: .now
        )
        do {
            try await store.save(sample)
        } catch {
            await post(.watchHydrationActionFailed)
            return .failed
        }
        WidgetCenter.shared.reloadAllTimelines()
        await post(HydrationNotification.actionHandled)
        return .logged(milliliters: glassML)
    }

    /// Observers rely on these signals arriving on the main actor.
    private static func post(_ name: Notification.Name) async {
        await MainActor.run {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }
}
