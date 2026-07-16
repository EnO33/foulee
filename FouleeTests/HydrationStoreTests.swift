import Dependencies
import Foundation
import Testing
@testable import Foulee

@Suite("HydrationStore")
struct HydrationStoreTests {
    struct Boom: Error, LocalizedError {
        var errorDescription: String? { "Santé a refusé l'écriture" }
    }

    @Test("A failed water write surfaces lastError instead of vanishing")
    @MainActor
    func failedWriteSurfacesLastError() async {
        await withDependencies {
            var client = HealthKitClient.testValue
            client.logWater = { _ in throw Boom() }
            $0.healthKit = client
        } operation: {
            let store = HydrationStore()
            await store.logGlass(ml: 250)

            #expect(store.lastError == "Santé a refusé l'écriture")
            #expect(store.writeDenied == false)
        }
    }

    @Test("A denied authorization blocks the save and raises writeDenied")
    @MainActor
    func deniedAuthorizationBlocksSave() async {
        let didAttemptSave = LockedRef(false)
        await withDependencies {
            var client = HealthKitClient.testValue
            client.waterWriteDenied = { true }
            client.logWater = { _ in didAttemptSave.set(true) }
            $0.healthKit = client
        } operation: {
            let store = HydrationStore()
            await store.logGlass(ml: 250)

            #expect(store.writeDenied == true)
            #expect(didAttemptSave.value == false)
            #expect(store.lastError == nil)
        }
    }

    @Test("Refresh exposes the denied write status alongside the intake")
    @MainActor
    func refreshExposesWriteDenied() async {
        await withDependencies {
            var client = HealthKitClient.testValue
            client.waterWriteDenied = { true }
            client.todayWaterML = { 750 }
            $0.healthKit = client
        } operation: {
            let store = HydrationStore()
            await store.refresh()

            #expect(store.intakeML == 750)
            #expect(store.writeDenied == true)
        }
    }
}

@Suite("HydrationNotificationCenter", .serialized)
struct HydrationNotificationCenterTests {
    @Test("A denied authorization stamps 'failed' and never fakes a logged glass")
    func deniedActionStampsFailure() async throws {
        let suiteName = "HydrationNotificationCenterTests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(200, forKey: "preferences.hydrationGlassML")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let didAttemptSave = LockedRef(false)
        var client = HealthKitClient.testValue
        client.waterWriteDenied = { true }
        client.logWater = { _ in didAttemptSave.set(true) }
        let center = HydrationNotificationCenter(healthKit: client, defaults: defaults)

        // The confirmation stamp lands in the standard defaults (shared with
        // the toast) — clear it around the assertion.
        UserDefaults.standard.removeObject(forKey: HydrationNotification.confirmKey)
        defer { UserDefaults.standard.removeObject(forKey: HydrationNotification.confirmKey) }

        await center.handle(action: HydrationNotification.drankAction)

        #expect(didAttemptSave.value == false)
        let stamp = UserDefaults.standard.dictionary(forKey: HydrationNotification.confirmKey)
        #expect(stamp?["kind"] as? String == "failed")
        #expect(stamp?["amount"] as? Int == 200)
    }

    @Test("A throwing water write stamps 'failed' too")
    func failedWriteStampsFailure() async throws {
        struct Boom: Error {}
        let suiteName = "HydrationNotificationCenterTests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var client = HealthKitClient.testValue
        client.logWater = { _ in throw Boom() }
        let center = HydrationNotificationCenter(healthKit: client, defaults: defaults)

        UserDefaults.standard.removeObject(forKey: HydrationNotification.confirmKey)
        defer { UserDefaults.standard.removeObject(forKey: HydrationNotification.confirmKey) }

        await center.handle(action: HydrationNotification.drankAction)

        let stamp = UserDefaults.standard.dictionary(forKey: HydrationNotification.confirmKey)
        #expect(stamp?["kind"] as? String == "failed")
        // No glass size in the defaults → the default 250 mL rides the stamp.
        #expect(stamp?["amount"] as? Int == 250)
    }
}
