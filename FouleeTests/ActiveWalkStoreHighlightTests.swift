import Dependencies
import FouleeKit
import Foundation
import Testing
@testable import Foulee

/// The end of an outing recorded on the iPhone (issues #529, #531): told by
/// its own screen, never by a notification.
@Suite("ActiveWalkStore — end of the outing")
struct ActiveWalkStoreHighlightTests {
    private static let frozen = Date(timeIntervalSince1970: 1_700_000_000)

    private func walk(endingDaysAgo days: Double, km: Double) -> WorkoutSummary {
        let end = Self.frozen.addingTimeInterval(-days * 86_400 + 1)
        return WorkoutSummary(
            id: UUID(),
            startedAt: end.addingTimeInterval(-km * 600),
            endedAt: end,
            durationSeconds: km * 600,
            distanceKm: km,
            activeCalories: 0,
            sourceName: "Foulée",
            activity: .walking
        )
    }

    private func run(workouts: [WorkoutSummary], recorded: LockedRef<[Date]>) async -> SessionHighlight? {
        await withDependencies {
            $0.date = .constant(Self.frozen)
            $0.pedometer = .testValue
            $0.continuousClock = TestClock()
            $0.healthKit.recentWorkouts = { _ in workouts }
            $0.sessionNotifications.recordedHere = { start, end in recorded.set([start, end]) }
        } operation: {
            let store = ActiveWalkStore()
            store.start()
            await store.stop()
            return store.highlight
        }
    }

    @Test("The outing goes on the register, and its best shows on the end screen")
    func highlightAndRegister() async {
        let recorded = LockedRef<[Date]>([])
        let history = [walk(endingDaysAgo: 3, km: 5), walk(endingDaysAgo: 6, km: 5), walk(endingDaysAgo: 9, km: 6)]
        let highlight = await run(workouts: history + [walk(endingDaysAgo: 0, km: 8.4)], recorded: recorded)
        #expect(recorded.value == [Self.frozen, Self.frozen])
        #expect(highlight?.title == "Ta plus longue marche depuis 6 mois")
        #expect(highlight?.body == "8,4 km aujourd'hui. La précédente faisait 6,0 km.")
    }

    @Test("Nothing better to say than its figures, or not in Santé: no highlight")
    func noHighlight() async {
        let recorded = LockedRef<[Date]>([])
        #expect(await run(workouts: [walk(endingDaysAgo: 0, km: 3)], recorded: recorded) == nil)
        #expect(await run(workouts: [], recorded: recorded) == nil)
    }
}
