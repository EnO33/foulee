import AppIntents
@preconcurrency import HealthKit
import WidgetKit

/// Resolves the user's glass size for surfaces that can't read the app's
/// preferences. `UserPreferences` lives in `UserDefaults.standard`, which the
/// widget process cannot read — the app mirrors the preference into the shared
/// snapshot and both sides resolve it from there.
enum WaterGlass {
    static let defaultML = 250

    static func milliliters(from snapshot: WidgetSnapshot?) -> Int {
        snapshot?.hydrationGlassML ?? defaultML
    }
}

/// Logs one glass of water to Apple Health. Compiled into the app *and* the
/// widget extension: the hydration widget's button runs it in the widget
/// process, so the ring updates instantly without opening the app; the app
/// target exposes it to Raccourcis / Siri via `FouleeShortcuts`.
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource { "J'ai bu un verre" }
    // periphery:ignore - read by the AppIntents runtime, never from code.
    static var description: IntentDescription { "Enregistre un verre d'eau dans Santé." }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .result(dialog: "Santé n'est pas disponible sur cet appareil.")
        }
        let store = HKHealthStore()
        let waterType = HKQuantityType(.dietaryWater)
        // Surface a denied write as a spoken/visible dialog instead of a
        // silent failure — the widget button otherwise looks broken.
        switch store.authorizationStatus(for: waterType) {
        case .sharingDenied:
            return .result(dialog: IntentDialog(
                "Foulée n'a pas l'autorisation d'écrire dans Santé. Active l'eau dans Santé > Profil > Apps > Foulée."
            ))
        case .notDetermined:
            return .result(dialog: "Ouvre d'abord Foulée pour autoriser l'accès à Santé.")
        default:
            break
        }

        let glassML = WaterGlass.milliliters(from: SharedStore.read())
        let sample = HKQuantitySample(
            type: waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(glassML)),
            start: .now,
            end: .now
        )
        try await store.save(sample)

        // Refresh the shared snapshot so every surface shows the new total.
        // Prefer HealthKit's own sum (it includes watch-logged water); fall
        // back to an optimistic increment when the store can't answer.
        let previousML = SharedStore.read()?.waterML ?? 0
        let totalML = await todayWaterML(store: store, type: waterType) ?? (previousML + glassML)
        SharedStore.updateWater(intakeML: totalML)
        // Targeted reload: only the hydration ring changed — don't spend the
        // other widgets' refresh budget.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.hydration)
        return .result(dialog: "C'est noté : +\(glassML) ml d'eau.")
    }

    /// Today's cumulative `dietaryWater` in millilitres, or nil when HealthKit
    /// can't answer. "No samples yet" is a real 0, not a failure.
    private func todayWaterML(store: HKHealthStore, type: HKQuantityType) async -> Int? {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error, (error as? HKError)?.code == .errorNoData {
                    continuation.resume(returning: 0)
                } else if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    let unit = HKUnit.literUnit(with: .milli)
                    continuation.resume(returning: Int(statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0))
                }
            }
            store.execute(query)
        }
    }
}
