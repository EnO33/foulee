import Foundation
import HealthKit

// HealthKit side of the soft Garmin detection (issue #185); the rules live in
// `GarminSource` / `GarminFreshness`. Separate file to keep
// HealthKitClient+Live.swift within the file-length limit.
//
// Every query builds its own `NSPredicate` from plain dates. `NSPredicate`
// isn't `Sendable`, so handing one to several `async let` branches is a data
// race the compiler rejects — the dates travel, the predicate doesn't.

/// Resolves — and caches for the app session — which watch writes the user's
/// Health data, then reports today's Garmin freshness on demand.
///
/// The "which watch" verdict barely moves during a run and costs three
/// queries, so it's resolved once; a user who connects Garmin Connect
/// mid-session gets the adapted hints on the next launch, which is soon enough
/// for a hint. The freshness date, by contrast, is re-read on every call — it
/// *is* the signal.
actor GarminSourceDetector {
    /// How far back detection looks for a source. Wide enough to survive a
    /// week of not opening Garmin Connect, short enough that a watch the user
    /// stopped wearing months ago stops counting.
    private static let detectionWindowDays = 30

    /// Outcome of the "which watch" probe. The matching `HKSource`s are kept
    /// so the freshness query can target them with `predicateForObjects(from:)`
    /// instead of scanning every sample of the day.
    private struct Devices: Sendable {
        var garminSources: Set<HKSource> = []
        var hasAppleWatch = false
        /// Every query answered. A failure — typically "authorization not
        /// determined" on the very first launch — means *no verdict yet*, and
        /// must not be frozen into the session cache.
        var isConclusive = true

        var hasGarmin: Bool { !garminSources.isEmpty }
    }

    private var cachedDevices: Devices?
    /// In-flight probe, so overlapping refreshes share one round of queries
    /// instead of each firing their own.
    private var probe: Task<Devices, Never>?

    func status(store: HKHealthStore) async -> GarminStatus {
        let devices = await resolvedDevices(store: store)
        guard devices.hasGarmin else {
            return GarminStatus(hasGarminSource: false, hasAppleWatchData: devices.hasAppleWatch)
        }
        return GarminStatus(
            hasGarminSource: true,
            hasAppleWatchData: devices.hasAppleWatch,
            latestGarminSample: await latestGarminSampleToday(
                store: store, sources: devices.garminSources
            )
        )
    }

    private func resolvedDevices(store: HKHealthStore) async -> Devices {
        if let cachedDevices { return cachedDevices }
        if let probe { return await probe.value }
        let task = Task { await Self.probeDevices(store: store) }
        probe = task
        let devices = await task.value
        probe = nil
        // Only a conclusive probe is worth a session-long cache: caching a
        // "no Garmin" derived from a query error would keep the adapted hints
        // off until the app is relaunched.
        if devices.isConclusive { cachedDevices = devices }
        return devices
    }

    private static func probeDevices(store: HKHealthStore) async -> Devices {
        let end = Date.now
        let start = Calendar.current.date(
            byAdding: .day, value: -detectionWindowDays, to: end
        ) ?? end
        // Garmin Connect writes both steps and workouts; asking for either
        // covers a user who only allowed one of the two in its Santé settings.
        async let steps = garminSources(
            store: store, type: HKQuantityType(.stepCount), start: start, end: end
        )
        async let workouts = garminSources(
            store: store, type: .workoutType(), start: start, end: end
        )
        async let watch = hasAppleWatchSamples(store: store, start: start, end: end)
        let stepSources = await steps
        let workoutSources = await workouts
        let appleWatch = await watch
        return Devices(
            garminSources: (stepSources ?? []).union(workoutSources ?? []),
            hasAppleWatch: appleWatch ?? false,
            isConclusive: stepSources != nil && workoutSources != nil && appleWatch != nil
        )
    }
}

/// Sources that wrote `type` in the window and look Garmin. `HKSourceQuery`
/// returns just the sources — no samples — so this stays cheap. `nil` means
/// the query failed and there is no verdict to cache.
private func garminSources(
    store: HKHealthStore,
    type: HKSampleType,
    start: Date,
    end: Date
) async -> Set<HKSource>? {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    return await withCheckedContinuation { continuation in
        let query = HKSourceQuery(sampleType: type, samplePredicate: predicate) { _, sources, error in
            guard error == nil, let sources else {
                continuation.resume(returning: nil)
                return
            }
            continuation.resume(returning: sources.filter {
                GarminSource.isGarmin(sourceName: $0.name, bundleIdentifier: $0.bundleIdentifier)
            })
        }
        store.execute(query)
    }
}

/// Whether the user has any Apple Watch step data in the window. Apple Watch
/// samples carry an `HKDevice` whose model is "Watch", which is the only
/// device fact HealthKit lets a predicate filter on. Samples written without a
/// device (rare, older data) are invisible here — the cost of a false negative
/// is one extra hint, never a missing feature. `nil` means the query failed.
private func hasAppleWatchSamples(
    store: HKHealthStore,
    start: Date,
    end: Date
) async -> Bool? {
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        HKQuery.predicateForSamples(withStart: start, end: end, options: []),
        HKQuery.predicateForObjects(
            withDeviceProperty: HKDevicePropertyKeyModel, allowedValues: ["Watch"]
        )
    ])
    return await withCheckedContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: HKQuantityType(.stepCount),
            predicate: predicate,
            limit: 1,
            sortDescriptors: nil
        ) { _, samples, error in
            guard error == nil, let samples else {
                continuation.resume(returning: nil)
                return
            }
            continuation.resume(returning: !samples.isEmpty)
        }
        store.execute(query)
    }
}

/// Newest sample the known Garmin sources wrote today, or `nil` when they
/// pushed nothing since midnight. Steps *and* workouts, because a user can
/// allow only one of the two in Garmin Connect — measuring the wrong stream
/// would report an eternal silence and nag forever.
private func latestGarminSampleToday(store: HKHealthStore, sources: Set<HKSource>) async -> Date? {
    let end = Date.now
    let start = Calendar.current.startOfDay(for: end)
    async let steps = newestSample(
        store: store, type: HKQuantityType(.stepCount), sources: sources, start: start, end: end
    )
    async let workouts = newestSample(
        store: store, type: .workoutType(), sources: sources, start: start, end: end
    )
    return [await steps, await workouts].compactMap { $0 }.max()
}

/// Start date of the newest `type` sample today written by `sources`. Filtered
/// by HealthKit (`predicateForObjects(from:)`) and capped at one result, so a
/// busy day doesn't drag thousands of samples into memory on every refresh.
private func newestSample(
    store: HKHealthStore,
    type: HKSampleType,
    sources: Set<HKSource>,
    start: Date,
    end: Date
) async -> Date? {
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
        HKQuery.predicateForObjects(from: sources)
    ])
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
    return await withCheckedContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            continuation.resume(returning: samples?.first?.startDate)
        }
        store.execute(query)
    }
}
