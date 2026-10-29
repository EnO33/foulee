import Testing
@testable import FouleeKit

/// When an outing on the wrist must end before the battery ends it (issue #614).
@Suite("Battery reading")
struct BatteryReadingTests {
    @Test("A battery at or under the critical level ends the outing")
    func criticalLevel() {
        #expect(BatteryReading(level: 0.05, isCharging: false).isCritical)
        #expect(BatteryReading(level: 0.01, isCharging: false).isCritical)
        #expect(BatteryReading(level: 0, isCharging: false).isCritical)
    }

    @Test("A battery above the critical level lets the outing run")
    func aboveCriticalLevel() {
        #expect(!BatteryReading(level: 0.06, isCharging: false).isCritical)
        #expect(!BatteryReading(level: 1, isCharging: false).isCritical)
    }

    @Test("A watch on its charger is never out of battery")
    func charging() {
        #expect(!BatteryReading(level: 0.02, isCharging: true).isCritical)
    }

    @Test("An unknown level never ends an outing")
    func unknownLevel() {
        #expect(!BatteryReading(level: -1, isCharging: false).isCritical)
    }
}
