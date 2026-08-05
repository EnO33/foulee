import Dependencies
import Foundation

/// A Garmin device the user authorized through Garmin Connect Mobile.
///
/// The SDK's own `IQDevice` is an Objective-C reference type; this is the
/// value-type projection the rest of the app sees. `Codable` because the
/// authorized set has to survive a relaunch: after a background BLE wake the
/// app must re-register its listeners without sending the user through the
/// Garmin Connect round-trip again.
struct GarminDevice: Codable, Equatable, Sendable {
    var id: UUID
    var modelName: String
    var friendlyName: String
}

/// Constants the SDK needs at initialization time.
enum GarminConnectIQConfiguration {
    /// URL scheme Garmin Connect Mobile calls back with the device-selection
    /// response. Declared in `Project.swift` as `garminReturnURLScheme` — the
    /// two must stay equal, and there is no compiler check for that.
    static let returnURLScheme = "foulee-ciq"

    /// Passed to the SDK as `CBCentralManagerOptionRestoreIdentifierKey`. With
    /// it (plus the `bluetooth-central` background mode) iOS relaunches the app
    /// in the background when the watch has data — see TN3115.
    static let stateRestorationIdentifier = "com.eno33.foulee.connectiq"

    /// UUID of the Foulée Monkey C app, read from its `manifest.xml`.
    ///
    /// Placeholder: the watch app doesn't exist yet (#188). Until it is
    /// generated, listener registration is a no-op in practice — no app on any
    /// device will ever match this id — which is exactly the intended
    /// behaviour for this spike.
    static let applicationUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")

    /// Whether a URL the app was opened with is the Garmin device-selection
    /// response. Pure, so the routing decision is testable — it also keeps the
    /// `foulee://` widget deep links from ever reaching the SDK parser.
    static func isDeviceSelectionResponse(_ url: URL) -> Bool {
        url.scheme?.lowercased() == returnURLScheme
    }
}

/// The Connect IQ companion SDK as a struct of closures.
///
/// Scope of #187 stops at "a snapshot arrived and decoded". Nothing here
/// writes to HealthKit or to the widget snapshot — merging Garmin data into
/// the app's own totals without double-counting is #189.
struct GarminConnectIQClient: Sendable {
    /// Initializes the SDK singleton (URL scheme + BLE state-restoration id).
    /// Idempotent; must run at process start, including on a background wake.
    var initialize: @Sendable () -> Void

    // periphery:ignore - implemented and ready, deliberately not wired: the flow
    // needs a settings entry point and a `.onOpenURL` route, and #187 stops
    // before any UI. Wired by the ingestion issue (#189).
    /// Foregrounds Garmin Connect Mobile so the user can pick which paired
    /// devices to share. The app is backgrounded — and possibly suspended —
    /// by this call; the answer comes back through `handleDeviceSelection`.
    var presentDeviceSelection: @Sendable () -> Void

    // periphery:ignore - same as `presentDeviceSelection`: it is the other half
    // of the same unwired round-trip.
    /// Parses the URL Garmin Connect Mobile relaunched the app with, persists
    /// the authorized devices and starts listening to them. Returns the
    /// devices, or an empty array when the URL isn't a selection response.
    var handleDeviceSelection: @Sendable (URL) -> [GarminDevice]

    // periphery:ignore - the listing exists for the settings screen that will
    // show "montre appairée" (#189); the live path reads the store directly.
    /// Devices authorized in a previous session.
    var knownDevices: @Sendable () -> [GarminDevice]

    /// Registers message listeners for the Foulée app on every known device.
    /// Idempotent, and cheap enough to call on every launch.
    var startReceiving: @Sendable () -> Void

    /// Snapshots as they are decoded. Undecodable messages are dropped
    /// silently — a foreign or malformed payload is not an app error.
    var snapshots: @Sendable () -> AsyncStream<GarminDailySnapshot>
}

extension GarminConnectIQClient: DependencyKey {
    static let previewValue = GarminConnectIQClient(
        initialize: {},
        presentDeviceSelection: {},
        handleDeviceSelection: { _ in [] },
        knownDevices: {
            [GarminDevice(id: UUID(), modelName: "Forerunner 965", friendlyName: "Ma Forerunner")]
        },
        startReceiving: {},
        snapshots: { AsyncStream { $0.finish() } }
    )

    static let testValue = GarminConnectIQClient(
        initialize: {},
        presentDeviceSelection: {},
        handleDeviceSelection: { _ in [] },
        knownDevices: { [] },
        startReceiving: {},
        snapshots: { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var garminConnectIQ: GarminConnectIQClient {
        get { self[GarminConnectIQClient.self] }
        set { self[GarminConnectIQClient.self] = newValue }
    }
}

/// Persistence of the authorized device set. Same shape as `WatchSyncStore`:
/// the `defaults` parameter is a test seam, production always takes the
/// default. Not the app group — the widget has no business talking BLE.
enum GarminDeviceStore {
    private static let key = "garmin.connectiq.devices"

    static func write(_ devices: [GarminDevice], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: key)
    }

    static func read(from defaults: UserDefaults = .standard) -> [GarminDevice] {
        guard let data = defaults.data(forKey: key),
              let devices = try? JSONDecoder().decode([GarminDevice].self, from: data) else { return [] }
        return devices
    }
}
