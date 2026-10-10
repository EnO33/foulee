import Foundation
import HealthKit

/// The water reads behind the Hydratation screen (issue #355), apart from
/// `HealthKitClient+Live` so that file stays one screen of wiring.

private let waterType = HKQuantityType(.dietaryWater)
private let milliliter = HKUnit.literUnit(with: .milli)

/// Today's `dietaryWater` samples, oldest first, from every source.
func waterSamplesToday(store: HKHealthStore) async throws -> [WaterSample] {
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
func dailyWater(store: HKHealthStore, daysBack: Int) async throws -> [MetricPoint] {
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
