import FouleeKit
import Foundation
import Testing
@testable import Foulee

/// What the detail of an outing offers to merge, and says before it does
/// (issue #552).
@Suite("Outing merge in the detail")
struct WorkoutDetailMergeTests {
    /// In the device's own time zone, which `clockText` prints in.
    private static func at(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: hour, minute: minute))!
    }

    private static func outing(from start: Date, minutes: Double, km: Double) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            durationSeconds: minutes * 60,
            distanceKm: km,
            activeCalories: 0,
            sourceName: "Foulée",
            activity: .walking
        )
    }

    @Test("A neighbour is named by the hour it began")
    func title() {
        let other = Self.outing(from: Self.at(hour: 10, minute: 42), minutes: 20, km: 1.5)
        #expect(WorkoutDetailMerge.mergeTitle(with: other) == "Fusionner avec la sortie de 10:42")
    }

    @Test("The confirmation says what the merge gives, whichever part was opened")
    func confirmation() {
        let first = Self.outing(from: Self.at(hour: 8, minute: 0), minutes: 30, km: 3.1)
        let second = Self.outing(from: Self.at(hour: 8, minute: 42), minutes: 30, km: 2.1)
        let expected = "08:00 → 09:12 · 5,2 km au total. Santé n'est pas modifié : tu pourras les séparer à nouveau."
        #expect(WorkoutDetailMerge.confirmation(merging: first, with: second) == expected)
        #expect(WorkoutDetailMerge.confirmation(merging: second, with: first) == expected)
    }

    @Test("Nothing to offer is no block at all")
    func emptyOptions() {
        let none = OutingMergeOptions(previous: nil, next: nil, isMerged: false, merge: { _ in }, separate: {})
        #expect(none.isEmpty)
        var merged = none
        merged.isMerged = true
        #expect(!merged.isEmpty)
    }
}
