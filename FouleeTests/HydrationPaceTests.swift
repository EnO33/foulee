import Foundation
import Testing
@testable import Foulee

/// Where the day's intake stands against the hydration window (issue #353).
@Suite("Hydration pace")
struct HydrationPaceTests {
    /// 9 h → 21 h: twelve hours, so 2 L is 250 ml every hour and a half.
    private let window = HydrationPace.Window(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 21, minute: 0))

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour, minute: minute))!
    }

    private func pace(_ intakeML: Int, at now: Date) -> HydrationPace {
        HydrationPace.evaluate(intakeML: intakeML, goalML: 2_000, glassML: 250, window: window, now: now, calendar: calendar)
    }

    @Test("Before the window, nothing drunk: the day has not started")
    func beforeTheWindow() {
        #expect(pace(0, at: at(7)) == .notStarted(TimeOfDay(hour: 9, minute: 0)))
        #expect(pace(0, at: at(7)).text == "Ta journée d'hydratation commence à 9 h")
    }

    @Test("A glass before the window is ahead")
    func earlyGlass() {
        #expect(pace(250, at: at(7)) == .ahead)
    }

    @Test("Halfway through the window, half the goal is on track")
    func onTrack() {
        #expect(pace(1_000, at: at(15)) == .onTrack)
        // Less than a glass off either way is still on track.
        #expect(pace(800, at: at(15)) == .onTrack)
        #expect(pace(1_200, at: at(15)) == .onTrack)
    }

    @Test("Whole glasses behind are counted down")
    func behind() {
        #expect(pace(500, at: at(15)) == .behind(glasses: 2))
        #expect(pace(750, at: at(15)) == .behind(glasses: 1))
        #expect(pace(750, at: at(15)).text == "Un verre de retard")
        #expect(pace(500, at: at(15)).text == "2 verres de retard")
    }

    @Test("A glass more than expected is ahead")
    func ahead() {
        #expect(pace(1_250, at: at(15)) == .ahead)
    }

    @Test("After the window, the whole goal is expected")
    func afterTheWindow() {
        #expect(pace(1_500, at: at(22)) == .behind(glasses: 2))
    }

    @Test("The goal met outranks the clock")
    func reached() {
        #expect(pace(2_000, at: at(10)) == .reached)
        #expect(pace(2_400, at: at(7)) == .reached)
    }

    @Test("A window that ends before it starts is over once started")
    func invertedWindow() {
        let inverted = HydrationPace.Window(start: TimeOfDay(hour: 21, minute: 0), end: TimeOfDay(hour: 9, minute: 0))
        #expect(HydrationPace.elapsedFraction(of: inverted, at: at(22), calendar: calendar) == 1)
        #expect(HydrationPace.elapsedFraction(of: inverted, at: at(8), calendar: calendar) == 0)
    }

    @Test("A start on the half hour is said with its minutes")
    func halfHourStart() {
        #expect(HydrationPace.notStarted(TimeOfDay(hour: 8, minute: 30)).text == "Ta journée d'hydratation commence à 8 h 30")
    }
}
