import FouleeKit
import Foundation
import HealthKit

/// The water reads behind the Hydratation screen (issue #355), the delete
/// behind « Annuler » (#354) and the Garmin watch's glasses (ADR 0009, D8),
/// apart from `HealthKitClient+Live` so that file stays one screen of wiring.

nonisolated private let waterType = HKQuantityType(.dietaryWater)
nonisolated private let milliliter = HKUnit.literUnit(with: .milli)

/// Today's `dietaryWater` samples, oldest first, from every source.
nonisolated func waterSamplesToday(store: HKHealthStore) async throws -> [WaterSample] {
    let start = Calendar.current.startOfDay(for: .now)
    let descriptor = HKSampleQueryDescriptor(
        predicates: [.quantitySample(
            type: waterType,
            predicate: HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        )],
        sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
    )
    do {
        return try await descriptor.result(for: store).map {
            WaterSample(
                id: $0.uuid,
                date: $0.startDate,
                milliliters: Int($0.quantity.doubleValue(for: milliliter).rounded()),
                sourceName: $0.sourceRevision.source.name
            )
        }
    } catch where isNoDataAvailable(error) {
        return []
    }
}

/// Daily `dietaryWater` totals over the last `daysBack` days, today included.
nonisolated func dailyWater(store: HKHealthStore, daysBack: Int) async throws -> [MetricPoint] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    guard daysBack > 0,
          let start = calendar.date(byAdding: .day, value: -(daysBack - 1), to: today),
          let end = calendar.date(byAdding: .day, value: 1, to: today)
    else { return [] }
    return try await statisticsCollection(
        store: store,
        mapping: HKMetricMapping(type: waterType, unit: milliliter, scale: 1),
        start: start,
        end: end,
        interval: DateComponents(day: 1)
    )
}

/// Delete the one `dietaryWater` sample `id`. A sample that is already gone
/// deletes nothing and is not an error: the glass is not there either way.
nonisolated func deleteWaterSample(store: HKHealthStore, id: UUID) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        store.deleteObjects(of: waterType, predicate: HKQuery.predicateForObject(with: id)) { _, _, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}

/// Writes a glass at `date`, unless Santé already holds one with
/// `syncIdentifier`.
///
/// Looked up first rather than left to the sync version alone: HealthKit
/// documents that a *greater* version replaces the sample it finds, and says
/// nothing of an equal one. The identifier and its version still go in the
/// metadata, so Santé knows the glass by them too. Should reading water be
/// refused, the lookup finds nothing and the write goes ahead: a glass is then
/// at worst written again, never lost.
nonisolated func logWaterOnce(
    store: HKHealthStore,
    milliliters: Int,
    date: Date,
    syncIdentifier: String
) async throws {
    let existing = HKSampleQueryDescriptor(
        predicates: [.quantitySample(
            type: waterType,
            predicate: HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                allowedValues: [syncIdentifier]
            )
        )],
        sortDescriptors: [],
        limit: 1
    )
    do {
        guard try await existing.result(for: store).isEmpty else { return }
    } catch where isNoDataAvailable(error) {
        // Nothing matched: the glass is not there yet.
    }
    let sample = HKQuantitySample(
        type: waterType,
        quantity: HKQuantity(unit: milliliter, doubleValue: Double(milliliters)),
        start: date,
        end: date,
        metadata: [HKMetadataKeySyncIdentifier: syncIdentifier, HKMetadataKeySyncVersion: 1]
    )
    try await store.save(sample)
}
