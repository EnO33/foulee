import Foundation
import Testing
@testable import FouleeKit

@Suite("Garmin pending outings")
struct GarminPendingOutingsTests {
    private static let noon = Date(timeIntervalSince1970: 1_760_961_600)

    private static func outing(at start: Date, minutes: Double = 30) -> GarminSessionSummary {
        GarminSessionSummary(
            activity: .walking,
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            durationSeconds: minutes * 60,
            distanceMeters: 2_400,
            steps: 3_100
        )
    }

    @Test("The same outing delivered twice is kept once, oldest first")
    func adding() {
        let early = Self.outing(at: Self.noon)
        let late = Self.outing(at: Self.noon.addingTimeInterval(3_600))
        let pending = GarminPendingOutings.adding(early, to: GarminPendingOutings.adding(late, to: []))
        #expect(GarminPendingOutings.adding(early, to: pending) == [early, late])
    }

    @Test("An outing goes once a Santé workout overlaps it")
    func coveredBySante() {
        let outing = Self.outing(at: Self.noon)
        let garminConnect = ActiveMinutes.WorkoutInterval(start: Self.noon.addingTimeInterval(20), duration: 1_790)
        let earlier = ActiveMinutes.WorkoutInterval(start: Self.noon.addingTimeInterval(-3_600), duration: 3_600)
        let now = Self.noon.addingTimeInterval(7_200)

        #expect(GarminPendingOutings.remaining([outing], healthKitWorkouts: [earlier], now: now) == [outing])
        #expect(GarminPendingOutings.remaining([outing], healthKitWorkouts: [garminConnect], now: now).isEmpty)
    }

    @Test("Past the streak's reach, or covering no clock, an outing goes")
    func expired() {
        let outing = Self.outing(at: Self.noon)
        let later = Self.noon.addingTimeInterval(GarminPendingOutings.horizon)
        #expect(GarminPendingOutings.remaining([outing], healthKitWorkouts: [], now: later).isEmpty)
        let empty = Self.outing(at: Self.noon, minutes: 0)
        #expect(GarminPendingOutings.remaining([empty], healthKitWorkouts: [], now: Self.noon).isEmpty)
    }

    @Test("Only the outings starting in the window count for it")
    func intervalsInWindow() {
        let inside = Self.outing(at: Self.noon)
        let before = Self.outing(at: Self.noon.addingTimeInterval(-86_400))
        let window = Self.noon.addingTimeInterval(-3_600)..<Self.noon.addingTimeInterval(3_600)
        #expect(GarminPendingOutings.intervals([before, inside], startingIn: window) == [inside.interval])
    }
}
