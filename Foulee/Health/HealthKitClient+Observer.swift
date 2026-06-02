@preconcurrency import HealthKit

/// Bridges `HKObserverQuery` to an `AsyncStream`: yields once per change to any
/// of `types` (and once shortly after starting, which also unsticks the very
/// first load). Foreground-only — no background-delivery entitlement needed.
/// Drives `HealthKitClient.observeChanges` so the Today dashboard updates live.
func healthChangeStream(store: HKHealthStore, types: [HKQuantityType]) -> AsyncStream<Void> {
    AsyncStream { continuation in
        let queries = types.map { type in
            HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                continuation.yield(())
                completion()
            }
        }
        queries.forEach { store.execute($0) }
        continuation.onTermination = { _ in
            queries.forEach { store.stop($0) }
        }
    }
}
