import Testing
@testable import FouleeWatch

/// The one piece of arithmetic on the session's « Journée » page (issue #280).
///
/// Small, but both edge cases are real: a goal of zero comes from a payload
/// written by an older phone build, and a day past its goal is the ordinary
/// case by mid-afternoon.
@Suite("Session day page progress")
struct WatchSessionDayPageTests {
    @Test("Half the goal is half the bar")
    func halfway() {
        #expect(WatchSessionDayPage.fraction(5_000, of: 10_000) == 0.5)
    }

    /// `ProgressView` draws `NaN` as a bar stuck empty with nothing to say why.
    @Test("A goal of zero gives an empty bar, never a NaN")
    func zeroGoalIsEmpty() {
        let value = WatchSessionDayPage.fraction(8_240, of: 0)
        #expect(value == 0)
        #expect(value.isNaN == false)
    }

    @Test("A goal already passed fills the bar rather than overflowing it")
    func pastTheGoalClamps() {
        #expect(WatchSessionDayPage.fraction(14_000, of: 10_000) == 1)
    }

    @Test("Nothing done yet is an empty bar, not an absent one")
    func zeroValue() {
        #expect(WatchSessionDayPage.fraction(0, of: 10_000) == 0)
    }
}
