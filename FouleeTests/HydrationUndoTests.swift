import Dependencies
import Foundation
import Testing
@testable import Foulee

/// Taking a glass back (issue #354).
@Suite("Hydration undo", .serialized)
struct HydrationUndoTests {
    struct Refused: Error {}

    private func scratchDefaults() throws -> UserDefaults {
        let name = "HydrationUndoTests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("A logged glass's stamp carries what it takes to undo it")
    func stampRoundTrip() {
        let sample = UUID()
        let stamp: [String: Any] = ["kind": "drank", "amount": 250, "sample": sample.uuidString, "previousDrinkAt": 1_000.0]
        #expect(
            HydrationNotification.Undo(stamp: stamp)
                == HydrationNotification.Undo(sample: sample, milliliters: 250, previousDrinkAt: 1_000)
        )
        #expect(HydrationNotification.Undo(stamp: ["kind": "snooze", "amount": 15]) == nil)
    }

    @Test("Undoing a glass puts the drink before it back, or none")
    func schedulerRestoresThePreviousDrink() async throws {
        let defaults = try scratchDefaults()
        let scheduler = HydrationReminderScheduler()

        let first = await scheduler.recordDrinkAndReschedule(defaults: defaults, now: Date(timeIntervalSince1970: 1_000))
        #expect(first == nil)
        let second = await scheduler.recordDrinkAndReschedule(defaults: defaults, now: Date(timeIntervalSince1970: 2_000))
        #expect(second == 1_000)

        await scheduler.restoreDrinkAndReschedule(previous: second, defaults: defaults)
        #expect(defaults.double(forKey: HydrationReminderScheduler.lastDrinkKey) == 1_000)

        await scheduler.restoreDrinkAndReschedule(previous: nil, defaults: defaults)
        #expect(defaults.object(forKey: HydrationReminderScheduler.lastDrinkKey) == nil)
    }

    @Test("Undo deletes the glass's own sample and re-reads the intake")
    @MainActor
    func storeDeletesTheSample() async {
        let sample = UUID()
        let deleted = LockedRef<[UUID]>([])
        await withDependencies {
            var client = HealthKitClient.testValue
            client.deleteWater = { deleted.set(deleted.value + [$0]) }
            client.todayWaterML = { 500 }
            $0.healthKit = client
        } operation: {
            let store = HydrationStore()
            let undone = await store.undo(.init(sample: sample, milliliters: 250, previousDrinkAt: nil))

            #expect(undone)
            #expect(deleted.value == [sample])
            #expect(store.intakeML == 500)
        }
    }

    @Test("A refused delete says so and leaves the intake alone")
    @MainActor
    func refusedDelete() async {
        await withDependencies {
            var client = HealthKitClient.testValue
            client.deleteWater = { _ in throw Refused() }
            client.todayWaterML = { 750 }
            $0.healthKit = client
        } operation: {
            let store = HydrationStore()
            let undone = await store.undo(.init(sample: UUID(), milliliters: 250, previousDrinkAt: nil))

            #expect(!undone)
            #expect(store.intakeML == 0)
        }
    }
}

/// In the notification center's own suite: it is serialized, and the stamp
/// lives in the standard defaults both share.
extension HydrationNotificationCenterTests {
    @Test("A glass logged from the notification can be undone from the toast")
    func notificationStampCarriesTheSample() async throws {
        let suiteName = "HydrationNotificationCenterTests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(200, forKey: "preferences.hydrationGlassML")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sample = UUID()
        var client = HealthKitClient.testValue
        client.logWater = { _ in sample }
        let center = HydrationNotificationCenter(healthKit: client, defaults: defaults)

        UserDefaults.standard.removeObject(forKey: HydrationNotification.confirmKey)
        defer { UserDefaults.standard.removeObject(forKey: HydrationNotification.confirmKey) }

        await center.handle(action: HydrationNotification.drankAction)

        let stamp = try #require(UserDefaults.standard.dictionary(forKey: HydrationNotification.confirmKey))
        #expect(stamp["kind"] as? String == "drank")
        #expect(HydrationNotification.Undo(stamp: stamp)?.sample == sample)
        #expect(HydrationNotification.Undo(stamp: stamp)?.milliliters == 200)
    }
}
