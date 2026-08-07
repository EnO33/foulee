import Dependencies
import Foundation
import Testing
@testable import Foulee

@Suite("StreakCalendarStore error freshness")
struct StreakCalendarStoreTests {
    @Test("A transient failure clears once the next load succeeds")
    @MainActor
    func transientErrorClearsOnNextSuccess() async {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "Santé indisponible" }
        }
        let failing = LockedRef(true)
        await withDependencies {
            // The store reads the clock to decide which months it browses.
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = { _ in
                if failing.value { throw Boom() }
                return []
            }
        } operation: {
            let store = StreakCalendarStore(goalMinutes: 20, goalSteps: 6_000, activeDays: Weekday.workWeek)
            await store.load()
            #expect(store.lastError == "Santé indisponible")

            failing.set(false)
            await store.load()
            #expect(store.lastError == nil)
        }
    }
}
