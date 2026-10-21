import FouleeKit
import Foundation
import os

/// The glasses noted with « J'ai bu » at the Garmin watch, from their BLE
/// delivery to Santé (ADR 0009, D8).
///
/// **Kept before written.** The watch lets a glass go as soon as the phone has
/// it, so the glass is persisted on arrival and only removed once Santé holds
/// it: a write refused (the phone locked, Santé busy) or a process killed in
/// between costs a delay, never the glass. Each arrival, and each launch,
/// retries everything still waiting.
///
/// **Written once.** `HealthKitClient.logSyncedWater` skips a glass whose
/// identifier Santé already has, so a glass redelivered after a lost
/// acknowledgement, or written just before the process died, counts once.
nonisolated enum GarminWaterIngestion {
    /// Drains what is waiting, then again at each arrival, until cancelled. One
    /// caller, at process start: the drains never overlap, so no glass is
    /// written by two of them at once.
    static func run(_ arrivals: AsyncStream<Void>, healthKit: HealthKitClient) async {
        await drain(healthKit: healthKit)
        for await _ in arrivals {
            await drain(healthKit: healthKit)
        }
    }

    /// Writes the waiting glasses, oldest first, and lets go of those Santé
    /// now holds. The first refusal stops the pass: the next ones would meet
    /// the same locked phone.
    static func drain(healthKit: HealthKitClient, defaults: UserDefaults = .standard) async {
        var written: [GarminWaterGlass] = []
        for glass in GarminWaterStore.read(from: defaults) {
            do {
                try await healthKit.logSyncedWater(glass.milliliters, glass.loggedAt, glass.syncIdentifier)
                written.append(glass)
            } catch {
                break
            }
        }
        GarminWaterStore.remove(written, from: defaults)
    }
}

/// The glasses waiting for Santé, in `UserDefaults.standard` like the other
/// Garmin stores: iOS wakes the app on BLE activity and kills it again. Behind
/// a lock, because the SDK's queue adds while the drain removes.
nonisolated enum GarminWaterStore {
    private static let key = "garmin.connectiq.pendingWater"
    private static let lock = OSAllocatedUnfairLock<Void>()

    static func add(_ glass: GarminWaterGlass, to defaults: UserDefaults = .standard) {
        lock.withLockUnchecked {
            write(GarminWaterGlass.adding(glass, to: read(from: defaults)), to: defaults)
        }
    }

    static func remove(_ glasses: [GarminWaterGlass], from defaults: UserDefaults = .standard) {
        guard !glasses.isEmpty else { return }
        let ids = Set(glasses.map(\.id))
        lock.withLockUnchecked {
            write(read(from: defaults).filter { !ids.contains($0.id) }, to: defaults)
        }
    }

    static func read(from defaults: UserDefaults = .standard) -> [GarminWaterGlass] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([GarminWaterGlass].self, from: data)) ?? []
    }

    private static func write(_ glasses: [GarminWaterGlass], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(glasses) else { return }
        defaults.set(data, forKey: key)
    }
}
