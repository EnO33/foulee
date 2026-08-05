@preconcurrency import ConnectIQ
import Foundation
import os

/// Bridges the Objective-C Connect IQ SDK to the app's value types.
///
/// `@unchecked Sendable` for the same reason as `PhoneWatchSync`: the SDK
/// hands delegate callbacks back on its own queue, so all mutable state sits
/// behind one lock and nothing else is stored. The SDK's own types (`IQDevice`,
/// `IQApp`, the `ConnectIQ` singleton) never escape this file — everything
/// crossing out is a `Sendable` value.
///
/// Nothing here is exercisable in the simulator: the Connect IQ simulator only
/// speaks to Android companions, so the whole BLE path below is verifiable
/// only against a physical Garmin watch (#191).
final class GarminConnectIQBridge: NSObject, IQDeviceEventDelegate, IQAppMessageDelegate, @unchecked Sendable {
    static let shared = GarminConnectIQBridge()

    private struct State {
        var isInitialized = false
        /// Devices already registered with the SDK this process — registering
        /// twice would deliver every message twice.
        var registeredDeviceIDs: Set<UUID> = []
        var subscribers: [UUID: AsyncStream<GarminDailySnapshot>.Continuation] = [:]
        var lastAccepted: GarminDailySnapshot?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    override private init() {
        super.init()
    }

    /// Must run at process start — including when iOS relaunches the app in
    /// the background after BLE activity, which is exactly when there is no UI
    /// to trigger it. The restoration identifier is what makes that relaunch
    /// possible in the first place (TN3115): the SDK passes it to its internal
    /// `CBCentralManager` as `CBCentralManagerOptionRestoreIdentifierKey`.
    func initializeIfNeeded() {
        let isFirstCall = state.withLock { state -> Bool in
            defer { state.isInitialized = true }
            return !state.isInitialized
        }
        guard isFirstCall, let connectIQ = ConnectIQ.sharedInstance() else { return }
        // nil UI-override delegate: the SDK then shows its own "install Garmin
        // Connect" prompt. Overriding it would mean owning that UI, which is
        // out of scope here.
        connectIQ.initialize(
            withUrlScheme: GarminConnectIQConfiguration.returnURLScheme,
            uiOverrideDelegate: nil,
            stateRestorationIdentifier: GarminConnectIQConfiguration.stateRestorationIdentifier
        )
    }

    /// Foregrounds Garmin Connect Mobile. The app is backgrounded by this call
    /// and may be suspended before the answer comes back through the return
    /// URL scheme — so nothing may be kept in memory across it.
    func presentDeviceSelection() {
        initializeIfNeeded()
        ConnectIQ.sharedInstance()?.showDeviceSelection()
    }

    func handleDeviceSelection(_ url: URL) -> [GarminDevice] {
        guard GarminConnectIQConfiguration.isDeviceSelectionResponse(url) else { return [] }
        initializeIfNeeded()
        let parsed = ConnectIQ.sharedInstance()?.parseDeviceSelectionResponse(from: url) as? [IQDevice] ?? []
        let devices = parsed.map {
            GarminDevice(id: $0.uuid, modelName: $0.modelName, friendlyName: $0.friendlyName)
        }
        // Only overwrite on a non-empty answer: the user cancelling out of
        // Garmin Connect must not silently unpair what already worked.
        guard !devices.isEmpty else { return [] }
        GarminDeviceStore.write(devices)
        startReceiving()
        return devices
    }

    func startReceiving() {
        initializeIfNeeded()
        guard let connectIQ = ConnectIQ.sharedInstance(),
              let appUUID = GarminConnectIQConfiguration.applicationUUID else { return }
        for device in GarminDeviceStore.read() {
            let isNew = state.withLock { $0.registeredDeviceIDs.insert(device.id).inserted }
            guard isNew else { continue }
            let iqDevice = IQDevice(
                id: device.id,
                modelName: device.modelName,
                friendlyName: device.friendlyName
            )
            connectIQ.register(forDeviceEvents: iqDevice, delegate: self)
            // Store UUID == app UUID: Foulée's watch app is side-loaded during
            // development and only gets a distinct store id once published
            // (#190). The SDK only uses it to open the store page.
            let app = IQApp(uuid: appUUID, store: appUUID, device: iqDevice)
            connectIQ.register(forAppMessages: app, delegate: self)
        }
    }

    func snapshots() -> AsyncStream<GarminDailySnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { $0.subscribers[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.subscribers[id] = nil }
            }
        }
    }

    // MARK: - IQAppMessageDelegate

    /// Called by the SDK on its own queue. Decoding happens here, synchronously,
    /// so the untyped `Any` payload never crosses an isolation boundary — only
    /// the decoded `Sendable` snapshot does.
    func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard let message, let snapshot = GarminDailySnapshot.decode(message) else { return }
        let subscribers = state.withLock { state -> [AsyncStream<GarminDailySnapshot>.Continuation] in
            guard GarminDailySnapshot.supersedes(snapshot, lastAccepted: state.lastAccepted) else { return [] }
            state.lastAccepted = snapshot
            return Array(state.subscribers.values)
        }
        for subscriber in subscribers { subscriber.yield(snapshot) }
    }

    // MARK: - IQDeviceEventDelegate

    // Required for `getDeviceStatus` to work at all — the SDK only tracks a
    // device once something registered for its events. Nothing acts on the
    // transitions yet; surfacing "montre connectée" in the UI is a later issue.
    func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {}
}

extension GarminConnectIQClient {
    static let liveValue = GarminConnectIQClient(
        initialize: { GarminConnectIQBridge.shared.initializeIfNeeded() },
        presentDeviceSelection: { GarminConnectIQBridge.shared.presentDeviceSelection() },
        handleDeviceSelection: { GarminConnectIQBridge.shared.handleDeviceSelection($0) },
        knownDevices: { GarminDeviceStore.read() },
        startReceiving: { GarminConnectIQBridge.shared.startReceiving() },
        snapshots: { GarminConnectIQBridge.shared.snapshots() },
        todayOverlay: { GarminSnapshotStore.readFloor(now: $0) }
    )
}
