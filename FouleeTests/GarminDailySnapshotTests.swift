import Foundation
import Testing
@testable import Foulee

/// The decoder is the only part of the Connect IQ integration that can be
/// tested at all: the BLE channel needs a physical Garmin watch (the Connect IQ
/// simulator only talks to Android companions), so everything below stops at
/// "a message dictionary came in and this is what we made of it".
@Suite("Garmin daily snapshot decoding")
struct GarminDailySnapshotDecodingTests {
    private func validMessage(overrides: [String: Any] = [:]) -> [String: Any] {
        var message: [String: Any] = [
            "v": 1,
            "steps": 8_432,
            "distanceCm": 631_500,
            "activeMinutes": 47,
            "activeMinutesVigorous": 12,
            "calories": 512,
            "ts": 1_754_380_800,
            "gen": 7
        ]
        for (key, value) in overrides { message[key] = value }
        return message
    }

    @Test("A complete payload decodes field for field")
    func validPayload() throws {
        let snapshot = try #require(GarminDailySnapshot.decode(validMessage()))
        #expect(snapshot.steps == 8_432)
        #expect(snapshot.distanceCm == 631_500)
        #expect(snapshot.activeMinutes == 47)
        #expect(snapshot.activeMinutesVigorous == 12)
        #expect(snapshot.calories == 512)
        #expect(snapshot.timestamp == Date(timeIntervalSince1970: 1_754_380_800))
        #expect(snapshot.generation == 7)
    }

    @Test("A newer schema version is rejected whole rather than half-read")
    func unknownVersion() {
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["v": 2])) == nil)
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["v": 0])) == nil)
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["v": -1])) == nil)
    }

    @Test("A payload with no version at all is rejected")
    func missingVersion() {
        var message = validMessage()
        message.removeValue(forKey: "v")
        #expect(GarminDailySnapshot.decode(message) == nil)
    }

    @Test("Missing metrics fall back to zero instead of losing the snapshot")
    func missingMetrics() throws {
        var message = validMessage()
        for key in ["steps", "distanceCm", "activeMinutes", "activeMinutesVigorous", "calories"] {
            message.removeValue(forKey: key)
        }
        let snapshot = try #require(GarminDailySnapshot.decode(message))
        #expect(snapshot.steps == 0)
        #expect(snapshot.distanceCm == 0)
        #expect(snapshot.activeMinutes == 0)
        #expect(snapshot.activeMinutesVigorous == 0)
        #expect(snapshot.calories == 0)
        // The ordering keys survived — that's what makes the snapshot usable.
        #expect(snapshot.generation == 7)
    }

    @Test("Missing ordering keys are fatal to the snapshot")
    func missingOrderingKeys() {
        var withoutTimestamp = validMessage()
        withoutTimestamp.removeValue(forKey: "ts")
        #expect(GarminDailySnapshot.decode(withoutTimestamp) == nil)

        var withoutGeneration = validMessage()
        withoutGeneration.removeValue(forKey: "gen")
        #expect(GarminDailySnapshot.decode(withoutGeneration) == nil)
    }

    @Test("Wrong types never crash: metrics degrade, ordering keys reject")
    func wrongTypes() throws {
        let mangled = validMessage(overrides: [
            "steps": "8432",
            "distanceCm": NSNull(),
            "activeMinutes": ["nested": 1],
            "activeMinutesVigorous": [1, 2, 3],
            "calories": "beaucoup"
        ])
        let snapshot = try #require(GarminDailySnapshot.decode(mangled))
        #expect(snapshot.steps == 0)
        #expect(snapshot.distanceCm == 0)
        #expect(snapshot.activeMinutes == 0)
        #expect(snapshot.activeMinutesVigorous == 0)
        #expect(snapshot.calories == 0)

        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["v": "1"])) == nil)
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["ts": "hier"])) == nil)
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["gen": NSNull()])) == nil)
    }

    @Test("Non-finite numbers are rejected rather than trapped on conversion")
    func nonFiniteNumbers() throws {
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["ts": Double.nan])) == nil)
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["ts": Double.infinity])) == nil)
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["gen": Double.nan])) == nil)

        let snapshot = try #require(GarminDailySnapshot.decode(validMessage(overrides: ["steps": Double.nan])))
        #expect(snapshot.steps == 0)
    }

    @Test("An out-of-range number saturates instead of trapping")
    func saturatingConversion() throws {
        let snapshot = try #require(GarminDailySnapshot.decode(validMessage(overrides: ["steps": 1e30])))
        #expect(snapshot.steps == Int.max)
    }

    @Test("Negative metrics are clamped to zero")
    func negativeMetrics() throws {
        let snapshot = try #require(GarminDailySnapshot.decode(validMessage(overrides: [
            "steps": -5,
            "calories": -1_000
        ])))
        #expect(snapshot.steps == 0)
        #expect(snapshot.calories == 0)
    }

    @Test("A non-positive or negative-generation payload is rejected")
    func invalidOrderingValues() {
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["ts": 0])) == nil)
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["ts": -1])) == nil)
        #expect(GarminDailySnapshot.decode(validMessage(overrides: ["gen": -1])) == nil)
    }

    @Test("Unknown keys are ignored so the watch side can add fields freely")
    func extraKeys() throws {
        let snapshot = try #require(GarminDailySnapshot.decode(validMessage(overrides: [
            "waterML": 750,
            "floors": 12,
            "battery": "low",
            "": ["anything"]
        ])))
        #expect(snapshot.steps == 8_432)
        #expect(snapshot.activeMinutes == 47)
    }

    @Test("Floating-point metrics round to the nearest whole unit")
    func fractionalMetrics() throws {
        let snapshot = try #require(GarminDailySnapshot.decode(validMessage(overrides: [
            "steps": 8_432.6,
            "activeMinutes": 46.4
        ])))
        #expect(snapshot.steps == 8_433)
        #expect(snapshot.activeMinutes == 46)
    }

    @Test("A message that isn't a dictionary is rejected")
    func nonDictionaryMessage() {
        #expect(GarminDailySnapshot.decode("bonjour") == nil)
        #expect(GarminDailySnapshot.decode([1, 2, 3]) == nil)
        #expect(GarminDailySnapshot.decode(NSNull()) == nil)
        #expect(GarminDailySnapshot.decode([String: Any]()) == nil)
    }

    @Test("Non-string keys don't sink the whole dictionary")
    func mixedKeyTypes() throws {
        var message: [AnyHashable: Any] = validMessage()
        message[42] = "clé Monkey C non textuelle"
        let snapshot = try #require(GarminDailySnapshot.decode(message))
        #expect(snapshot.steps == 8_432)
    }
}

@Suite("Garmin snapshot ordering")
struct GarminSnapshotOrderingTests {
    private func snapshot(generation: Int, secondsSinceEpoch: TimeInterval) -> GarminDailySnapshot {
        GarminDailySnapshot(
            steps: 0,
            distanceCm: 0,
            activeMinutes: 0,
            activeMinutesVigorous: 0,
            calories: 0,
            timestamp: Date(timeIntervalSince1970: secondsSinceEpoch),
            generation: generation
        )
    }

    @Test("The first snapshot is always accepted")
    func firstSnapshot() {
        #expect(GarminDailySnapshot.supersedes(snapshot(generation: 0, secondsSinceEpoch: 1), lastAccepted: nil))
    }

    @Test("A newer generation wins")
    func newerGeneration() {
        let last = snapshot(generation: 4, secondsSinceEpoch: 1_000)
        #expect(GarminDailySnapshot.supersedes(snapshot(generation: 5, secondsSinceEpoch: 1_000), lastAccepted: last))
        // Even with an older timestamp: the watch's counter is the authority,
        // its clock can be resynchronised backwards.
        #expect(GarminDailySnapshot.supersedes(snapshot(generation: 5, secondsSinceEpoch: 10), lastAccepted: last))
    }

    @Test("An older generation is a stale redelivery")
    func olderGeneration() {
        let last = snapshot(generation: 4, secondsSinceEpoch: 1_000)
        #expect(!GarminDailySnapshot.supersedes(snapshot(generation: 3, secondsSinceEpoch: 9_999), lastAccepted: last))
    }

    @Test("Within one generation only a newer timestamp advances")
    func sameGeneration() {
        let last = snapshot(generation: 4, secondsSinceEpoch: 1_000)
        #expect(GarminDailySnapshot.supersedes(snapshot(generation: 4, secondsSinceEpoch: 1_001), lastAccepted: last))
        #expect(!GarminDailySnapshot.supersedes(snapshot(generation: 4, secondsSinceEpoch: 1_000), lastAccepted: last))
        #expect(!GarminDailySnapshot.supersedes(snapshot(generation: 4, secondsSinceEpoch: 999), lastAccepted: last))
    }
}

@Suite("Garmin Connect IQ configuration")
struct GarminConnectIQConfigurationTests {
    @Test("Only the Garmin return scheme is routed to the SDK parser")
    func deviceSelectionResponseRouting() throws {
        let returnURL = try #require(URL(string: "foulee-ciq://device-selection?devices=abc"))
        #expect(GarminConnectIQConfiguration.isDeviceSelectionResponse(returnURL))

        // The widget deep links share a prefix — they must never reach the SDK.
        let deepLink = try #require(URL(string: "foulee://hydration"))
        #expect(!GarminConnectIQConfiguration.isDeviceSelectionResponse(deepLink))

        let foreign = try #require(URL(string: "https://example.com"))
        #expect(!GarminConnectIQConfiguration.isDeviceSelectionResponse(foreign))
    }

    @Test("Scheme matching ignores case, as iOS does")
    func schemeCaseInsensitivity() throws {
        let shouted = try #require(URL(string: "FOULEE-CIQ://device-selection"))
        #expect(GarminConnectIQConfiguration.isDeviceSelectionResponse(shouted))
    }
}

@Suite("Garmin device store")
struct GarminDeviceStoreTests {
    @Test("Authorized devices survive a relaunch")
    func roundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "garmin.device.store.tests"))
        defaults.removePersistentDomain(forName: "garmin.device.store.tests")

        #expect(GarminDeviceStore.read(from: defaults).isEmpty)
        let devices = [
            GarminDevice(id: UUID(), modelName: "Forerunner 965", friendlyName: "Ma Forerunner"),
            GarminDevice(id: UUID(), modelName: "fenix 8", friendlyName: "La fēnix")
        ]
        GarminDeviceStore.write(devices, to: defaults)
        #expect(GarminDeviceStore.read(from: defaults) == devices)

        defaults.removePersistentDomain(forName: "garmin.device.store.tests")
    }

    @Test("Garbage in the store reads back as no devices, never as a crash")
    func corruptedStore() throws {
        let defaults = try #require(UserDefaults(suiteName: "garmin.device.store.corrupt.tests"))
        defaults.removePersistentDomain(forName: "garmin.device.store.corrupt.tests")

        defaults.set(Data("pas du JSON".utf8), forKey: "garmin.connectiq.devices")
        #expect(GarminDeviceStore.read(from: defaults).isEmpty)

        defaults.removePersistentDomain(forName: "garmin.device.store.corrupt.tests")
    }
}
