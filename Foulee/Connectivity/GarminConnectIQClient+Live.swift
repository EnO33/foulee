@preconcurrency import ConnectIQ
import FouleeKit
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
nonisolated final class GarminConnectIQBridge: NSObject, IQDeviceEventDelegate, IQAppMessageDelegate, @unchecked Sendable {
    static let shared = GarminConnectIQBridge()

    nonisolated private struct State {
        var isInitialized = false
        /// Devices already registered with the SDK this process — registering
        /// twice would deliver every message twice.
        var registeredDeviceIDs: Set<UUID> = []
        var subscribers: [UUID: AsyncStream<GarminDailySnapshot>.Continuation] = [:]
        var sessionSubscribers: [UUID: AsyncStream<WatchSessionSnapshot>.Continuation] = [:]
        var waterSubscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
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
        guard let connectIQ = ConnectIQ.sharedInstance() else { return }
        for device in GarminDeviceStore.read() {
            let isNew = state.withLock { $0.registeredDeviceIDs.insert(device.id).inserted }
            guard isNew else { continue }
            let iqDevice = Self.iqDevice(device)
            connectIQ.register(forDeviceEvents: iqDevice, delegate: self)
            for app in Self.apps(on: iqDevice) {
                connectIQ.register(forAppMessages: app, delegate: self)
            }
        }
    }

    /// Pushes the phone-computed state to the Foulée app on every authorized
    /// watch (ADR 0009, D5). Fire and forget: a watch out of range, or without
    /// the app, misses this send and is put right by the next, since each one
    /// is the complete state. Nothing is sent before `initializeIfNeeded` ran,
    /// and sending must not be what initializes the SDK.
    func sendSync(_ payload: WatchSyncPayload) {
        guard state.withLock({ $0.isInitialized }), let connectIQ = ConnectIQ.sharedInstance() else { return }
        let message = GarminPhoneSync.message(from: payload)
        for device in GarminDeviceStore.read() {
            for app in Self.apps(on: Self.iqDevice(device)) {
                // The SDK calls both blocks unconditionally: nil would crash it.
                connectIQ.sendMessage(message, to: app, progress: { _, _ in }, completion: { _ in })
            }
        }
    }

    private static func iqDevice(_ device: GarminDevice) -> IQDevice {
        IQDevice(id: device.id, modelName: device.modelName, friendlyName: device.friendlyName)
    }

    /// The production and beta builds of the watch app on `device`. Store UUID
    /// == app UUID until the first publication hands out the store id (#481);
    /// the SDK only uses it to open the store page.
    private static func apps(on device: IQDevice) -> [IQApp] {
        GarminConnectIQConfiguration.applicationUUIDs.map { IQApp(uuid: $0, store: $0, device: device) }
    }

    func snapshots() -> AsyncStream<GarminDailySnapshot> {
        stream(of: \.subscribers)
    }

    func sessionStates() -> AsyncStream<WatchSessionSnapshot> {
        stream(of: \.sessionSubscribers)
    }

    func waterArrivals() -> AsyncStream<Void> {
        stream(of: \.waterSubscribers)
    }

    private func stream<Element: Sendable>(
        of subscribers: WritableKeyPath<State, [UUID: AsyncStream<Element>.Continuation]> & Sendable
    ) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { $0[keyPath: subscribers][id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0[keyPath: subscribers][id] = nil }
            }
        }
    }

    // MARK: - IQAppMessageDelegate

    /// Called by the SDK on its own queue. Decoding happens here, synchronously,
    /// so the untyped `Any` payload never crosses an isolation boundary — only
    /// the decoded `Sendable` snapshot does.
    func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard let message else { return }
        // A session saved on the watch: kept until Santé has the activity
        // Garmin Connect writes (ADR 0009, D2). The next HealthKit read counts
        // it; nothing is published from here.
        if let summary = GarminSessionSummary.decode(message) {
            GarminPendingOutingStore.add(summary)
            return
        }
        // A glass noted at the watch (ADR 0009, D8): kept before anything
        // else, since the watch lets it go once delivered; the drain then
        // writes it to Santé.
        if let glass = GarminWaterGlass.decode(message) {
            GarminWaterStore.add(glass)
            let subscribers = state.withLock { Array($0.waterSubscribers.values) }
            for subscriber in subscribers { subscriber.yield() }
            return
        }
        // The session in progress, for the mirror screen (ADR 0009, D7).
        // Every state goes through: `MirroredSessionStore` keeps the newest.
        if let session = GarminSessionState.decode(message) {
            let subscribers = state.withLock { Array($0.sessionSubscribers.values) }
            for subscriber in subscribers { subscriber.yield(session) }
            return
        }
        guard let snapshot = GarminDailySnapshot.decode(message) else { return }
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

nonisolated extension GarminConnectIQClient {
    static let liveValue = GarminConnectIQClient(
        initialize: { GarminConnectIQBridge.shared.initializeIfNeeded() },
        presentDeviceSelection: { GarminConnectIQBridge.shared.presentDeviceSelection() },
        handleDeviceSelection: { GarminConnectIQBridge.shared.handleDeviceSelection($0) },
        knownDevices: { GarminDeviceStore.read() },
        startReceiving: { GarminConnectIQBridge.shared.startReceiving() },
        snapshots: { GarminConnectIQBridge.shared.snapshots() },
        sessionStates: { GarminConnectIQBridge.shared.sessionStates() },
        waterArrivals: { GarminConnectIQBridge.shared.waterArrivals() },
        todayOverlay: { GarminSnapshotStore.readFloor(now: $0) }
    )
}
