import Foundation
import Testing
@testable import Foulee

/// The line that keeps the mirror screen honest (issue #279).
///
/// HealthKit caches what a mirrored session sends and wakes this app
/// periodically, potentially minutes apart, so « en direct » would be a lie for
/// most of an outing. The clock runs on its own — it is derived from a date —
/// while the counters carry the age of the last thing the wrist actually said.
@Suite("Mirrored walk freshness")
struct MirroredWalkScreenTests {
    /// Under a minute, « il y a 0 min » would read as a rounding bug rather
    /// than as freshness.
    @Test("Under a minute the figures read as just measured", arguments: [0.0, 1.0, 59.0])
    func freshFiguresSayNoNumber(age: TimeInterval) {
        #expect(MirroredWalkScreen.ageText(age) == "Relevé à l'instant")
    }

    @Test("From a minute on, the age is stated in minutes")
    func staleFiguresStateTheirAge() {
        #expect(MirroredWalkScreen.ageText(60) == "Relevé il y a 1 min")
        #expect(MirroredWalkScreen.ageText(119) == "Relevé il y a 1 min")
        #expect(MirroredWalkScreen.ageText(120) == "Relevé il y a 2 min")
    }

    /// Rounded down, never up: claiming figures are older than they are is
    /// harmless, claiming they are fresher is the failure this line prevents.
    @Test("The age is rounded down")
    func theAgeRoundsDown() {
        #expect(MirroredWalkScreen.ageText(3 * 60 + 59) == "Relevé il y a 3 min")
    }
}
