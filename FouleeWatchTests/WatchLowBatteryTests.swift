import FouleeKit
import Foundation
import Testing
@testable import FouleeWatch

/// An outing on the wrist ends itself before the battery does (issue #614):
/// a watch that switches off finishes nothing, and the outing is lost to Santé.
@MainActor
@Suite("Watch low battery")
struct WatchLowBatteryTests {
    private func savedFlag(_ store: WatchWorkoutStore) -> Bool? {
        guard case .ended(_, let saveFailed) = store.state else { return nil }
        return saveFailed
    }

    @Test("A critical battery ends the outing and saves it to Santé")
    func criticalBatteryEndsAndSaves() async throws {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.battery = BatteryReading(level: 0.04, isCharging: false)
        await store.endIfBatteryCritical()
        let saveFailed = try #require(savedFlag(store))
        #expect(!saveFailed)
        #expect(store.endedOnLowBattery)
        #expect(stub.endCollectionCalls == 1)
        #expect(stub.finishCalls == 1)
        #expect(stub.sentSnapshots.last?.isEnded == true)
    }

    @Test("A healthy battery lets the outing run")
    func healthyBatteryKeepsRunning() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.endIfBatteryCritical()
        #expect(savedFlag(store) == nil)
        #expect(!store.endedOnLowBattery)
        #expect(stub.finishCalls == 0)
    }

    @Test("A watch on its charger keeps recording, however low it reads")
    func chargingKeepsRunning() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.battery = BatteryReading(level: 0.02, isCharging: true)
        await store.endIfBatteryCritical()
        #expect(savedFlag(store) == nil)
        #expect(stub.finishCalls == 0)
    }

    @Test("A paused outing is ended and saved too")
    func pausedOutingEnds() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        store.pause()
        stub.battery = BatteryReading(level: 0.03, isCharging: false)
        await store.endIfBatteryCritical()
        #expect(savedFlag(store) == false)
        #expect(stub.finishCalls == 1)
    }

    @Test("Nothing to end when no outing is running")
    func idleDoesNothing() async {
        let stub = WorkoutHealthKitStub()
        stub.battery = BatteryReading(level: 0.01, isCharging: false)
        let store = stub.makeStore()
        await store.endIfBatteryCritical()
        #expect(store.state == .idle)
        #expect(!store.endedOnLowBattery)
    }

    @Test("A new outing forgets that the last one ran out of battery")
    func resetClearsTheReason() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        stub.battery = BatteryReading(level: 0.04, isCharging: false)
        await store.endIfBatteryCritical()
        store.reset()
        #expect(!store.endedOnLowBattery)
    }

    @Test("The summary says why the outing stopped, unless the save failed")
    func summaryReason() {
        let lowBattery = WatchFinishedView(
            metrics: .zero, saveFailed: false, endedOnLowBattery: true, onRetry: {}, onDone: {}
        )
        #expect(lowBattery.reasonText != nil)
        let failed = WatchFinishedView(
            metrics: .zero, saveFailed: true, errorMessage: "boom", endedOnLowBattery: true, onRetry: {}, onDone: {}
        )
        #expect(failed.reasonText == "boom")
        let ordinary = WatchFinishedView(metrics: .zero, saveFailed: false, onRetry: {}, onDone: {})
        #expect(ordinary.reasonText == nil)
    }
}
