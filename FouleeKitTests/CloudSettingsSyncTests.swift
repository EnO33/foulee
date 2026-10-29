import Foundation
import Testing
@testable import FouleeKit

@Suite("CloudSettingsSync")
struct CloudSettingsSyncTests {
    private let keys = ["preferences.minutesGoal", "preferences.themeMode"]
    private let stamp = CloudSettingsSync.modifiedAtKey

    /// Two throwaway suites, one standing for this iPhone's defaults and one
    /// for iCloud's store, removed afterwards.
    private func withStores(_ body: (UserDefaults, UserDefaults) throws -> Void) throws {
        let localName = "cloud-sync-local-\(UUID().uuidString)"
        let cloudName = "cloud-sync-cloud-\(UUID().uuidString)"
        let local = try #require(UserDefaults(suiteName: localName))
        let cloud = try #require(UserDefaults(suiteName: cloudName))
        defer {
            local.removePersistentDomain(forName: localName)
            cloud.removePersistentDomain(forName: cloudName)
        }
        try body(local, cloud)
    }

    @Test("A change here is stamped and sent, defaults removed included")
    func localChangePushes() throws {
        try withStores { local, cloud in
            cloud.set("dark", forKey: "preferences.themeMode")
            local.set(30, forKey: "preferences.minutesGoal")

            CloudSettingsSync.localDidChange(keys, local: local, cloud: cloud, now: Date(timeIntervalSince1970: 100))

            #expect(local.object(forKey: stamp) as? Double == 100)
            #expect(cloud.object(forKey: stamp) as? Double == 100)
            #expect(cloud.object(forKey: "preferences.minutesGoal") as? Int == 30)
            #expect(cloud.object(forKey: "preferences.themeMode") == nil)
        }
    }

    @Test("The newer cloud set replaces the local one whole")
    func newerCloudPulls() throws {
        try withStores { local, cloud in
            local.set(10.0, forKey: stamp)
            local.set(30, forKey: "preferences.minutesGoal")
            local.set("light", forKey: "preferences.themeMode")
            cloud.set(20.0, forKey: stamp)
            cloud.set(45, forKey: "preferences.minutesGoal")

            let outcome = CloudSettingsSync.reconcile(keys, local: local, cloud: cloud, seeds: true)

            #expect(outcome == .pulled)
            #expect(local.object(forKey: "preferences.minutesGoal") as? Int == 45)
            #expect(local.object(forKey: "preferences.themeMode") == nil)
            #expect(local.object(forKey: stamp) as? Double == 20)
        }
    }

    @Test("The newer local set goes up")
    func newerLocalPushes() throws {
        try withStores { local, cloud in
            local.set(30.0, forKey: stamp)
            local.set(25, forKey: "preferences.minutesGoal")
            cloud.set(20.0, forKey: stamp)
            cloud.set(45, forKey: "preferences.minutesGoal")

            #expect(CloudSettingsSync.reconcile(keys, local: local, cloud: cloud, seeds: true) == .pushed)
            #expect(cloud.object(forKey: "preferences.minutesGoal") as? Int == 25)
            #expect(cloud.object(forKey: stamp) as? Double == 30)
        }
    }

    @Test("Equal stamps leave both sides alone")
    func equalStampsUnchanged() throws {
        try withStores { local, cloud in
            local.set(20.0, forKey: stamp)
            local.set(25, forKey: "preferences.minutesGoal")
            cloud.set(20.0, forKey: stamp)
            cloud.set(45, forKey: "preferences.minutesGoal")

            #expect(CloudSettingsSync.reconcile(keys, local: local, cloud: cloud, seeds: true) == .unchanged)
            #expect(local.object(forKey: "preferences.minutesGoal") as? Int == 25)
        }
    }

    @Test("A new iPhone takes the settings of the others")
    func unstampedLocalPulls() throws {
        try withStores { local, cloud in
            local.set(20, forKey: "preferences.minutesGoal")
            cloud.set(0.0, forKey: stamp)
            cloud.set(45, forKey: "preferences.minutesGoal")

            #expect(CloudSettingsSync.reconcile(keys, local: local, cloud: cloud, seeds: false) == .pulled)
            #expect(local.object(forKey: "preferences.minutesGoal") as? Int == 45)
        }
    }

    @Test("An install from before the sync fills an empty cloud with the oldest stamp")
    func existingInstallSeeds() throws {
        try withStores { local, cloud in
            local.set(30, forKey: "preferences.minutesGoal")

            #expect(CloudSettingsSync.reconcile(keys, local: local, cloud: cloud, seeds: true) == .pushed)
            #expect(cloud.object(forKey: "preferences.minutesGoal") as? Int == 30)
            #expect(cloud.object(forKey: stamp) as? Double == 0)
            #expect(local.object(forKey: stamp) as? Double == 0)
        }
    }

    @Test("A new install's untouched defaults never fill the cloud")
    func newInstallDoesNotSeed() throws {
        try withStores { local, cloud in
            local.set(20, forKey: "preferences.minutesGoal")

            #expect(CloudSettingsSync.reconcile(keys, local: local, cloud: cloud, seeds: false) == .unchanged)
            #expect(cloud.object(forKey: "preferences.minutesGoal") == nil)
            #expect(local.object(forKey: stamp) == nil)
        }
    }

    @Test("A set under its own stamp never moves the settings' stamp")
    func separateStamp() throws {
        try withStores { local, cloud in
            let merges = ["outings.merges"]
            let mergesStamp = "outings.merges.modifiedAt"
            local.set(50.0, forKey: stamp)
            cloud.set(10.0, forKey: stamp)
            cloud.set(20.0, forKey: mergesStamp)
            cloud.set(Data([1]), forKey: "outings.merges")

            let outcome = CloudSettingsSync.reconcile(merges, local: local, cloud: cloud, seeds: false, stamp: mergesStamp)

            #expect(outcome == .pulled)
            #expect(local.object(forKey: "outings.merges") as? Data == Data([1]))
            #expect(local.object(forKey: mergesStamp) as? Double == 20)
            #expect(local.object(forKey: stamp) as? Double == 50)
            #expect(cloud.object(forKey: stamp) as? Double == 10)
        }
    }
}
