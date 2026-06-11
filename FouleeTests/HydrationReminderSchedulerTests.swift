import Foundation
import Testing
@testable import Foulee

@Suite struct HydrationReminderSchedulerTests {
    /// A throwaway suite so `lastDrinkToday` tests don't touch real prefs.
    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.hydration.\(UUID().uuidString)")!
    }

    // MARK: - Daily reset of the shifted grid

    @Test func lastDrinkFromTodayShiftsTheGrid() {
        let defaults = scratchDefaults()
        let now = Date(timeIntervalSince1970: 1_000_000)
        // A glass 40 min before "now".
        defaults.set(now.addingTimeInterval(-40 * 60).timeIntervalSince1970,
                     forKey: HydrationReminderScheduler.lastDrinkKey)
        #expect(HydrationReminderScheduler.lastDrinkToday(defaults: defaults, now: now) != nil)
    }

    @Test func lastDrinkFromYesterdayIsIgnored() {
        // The core of the daily-reset fix: a glass logged yesterday must NOT
        // keep shifting today's grid — lastDrinkToday returns nil, so
        // times(for:) falls back to the standard grid.
        let defaults = scratchDefaults()
        let now = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(now.addingTimeInterval(-26 * 3_600).timeIntervalSince1970,
                     forKey: HydrationReminderScheduler.lastDrinkKey)
        #expect(HydrationReminderScheduler.lastDrinkToday(defaults: defaults, now: now) == nil)
    }

    @Test func noDrinkStampIsIgnored() {
        let defaults = scratchDefaults()
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(HydrationReminderScheduler.lastDrinkToday(defaults: defaults, now: now) == nil)
    }

    @Test func everyTwoHoursFromNineToNine() {
        let times = HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 9 * 60),
            end: TimeOfDay(rawMinutes: 21 * 60),
            intervalMinutes: 120
        )
        // 9, 11, 13, 15, 17, 19, 21
        #expect(times.map(\.rawMinutes) == [540, 660, 780, 900, 1_020, 1_140, 1_260])
    }

    @Test func includesEndWhenItLandsOnInterval() {
        let times = HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 600),
            end: TimeOfDay(rawMinutes: 660),
            intervalMinutes: 30
        )
        #expect(times.map(\.rawMinutes) == [600, 630, 660])
    }

    @Test func stopsBeforeOvershootingEnd() {
        let times = HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 600),
            end: TimeOfDay(rawMinutes: 700),
            intervalMinutes: 60
        )
        // 600, 660 — 720 would overshoot 700
        #expect(times.map(\.rawMinutes) == [600, 660])
    }

    @Test func emptyForNonPositiveInterval() {
        #expect(HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 540),
            end: TimeOfDay(rawMinutes: 1_260),
            intervalMinutes: 0
        ).isEmpty)
    }

    @Test func emptyForInvertedWindow() {
        #expect(HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 1_260),
            end: TimeOfDay(rawMinutes: 540),
            intervalMinutes: 60
        ).isEmpty)
    }

    @Test func singleSlotWhenStartEqualsEnd() {
        let times = HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 540),
            end: TimeOfDay(rawMinutes: 540),
            intervalMinutes: 60
        )
        #expect(times.map(\.rawMinutes) == [540])
    }

    // MARK: - Grid shifted by the last glass

    @Test func drinkShiftsNextReminderAFullIntervalLater() {
        // Drink at 10:57, every 2 h between 9:00 and 21:00 →
        // 12:57, 14:57, 16:57, 18:57, 20:57 (not 11:00).
        let times = HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 9 * 60),
            end: TimeOfDay(rawMinutes: 21 * 60),
            intervalMinutes: 120,
            lastDrink: TimeOfDay(rawMinutes: 10 * 60 + 57)
        )
        #expect(times.map(\.rawMinutes) == [777, 897, 1_017, 1_137, 1_257])
    }

    @Test func noDrinkKeepsStandardGrid() {
        let times = HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 540),
            end: TimeOfDay(rawMinutes: 1_260),
            intervalMinutes: 120,
            lastDrink: nil
        )
        #expect(times.map(\.rawMinutes) == [540, 660, 780, 900, 1_020, 1_140, 1_260])
    }

    @Test func earlyDrinkBeforeWindowKeepsStandardGrid() {
        // Drink at 6:00 (+2 h = 8:00, before the 9:00 window start).
        let times = HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 540),
            end: TimeOfDay(rawMinutes: 1_260),
            intervalMinutes: 120,
            lastDrink: TimeOfDay(rawMinutes: 360)
        )
        #expect(times.map(\.rawMinutes) == [540, 660, 780, 900, 1_020, 1_140, 1_260])
    }

    @Test func lateDrinkFallsBackToStandardGridForTomorrow() {
        // Drink at 20:30 (+2 h = 22:30, past the 21:00 end) — keep the daily
        // repeating grid so tomorrow still has reminders.
        let times = HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 540),
            end: TimeOfDay(rawMinutes: 1_260),
            intervalMinutes: 120,
            lastDrink: TimeOfDay(rawMinutes: 20 * 60 + 30)
        )
        #expect(times.map(\.rawMinutes) == [540, 660, 780, 900, 1_020, 1_140, 1_260])
    }

    @Test func anchorLandingExactlyOnEndKeepsThatSlot() {
        // Drink at 19:00 (+2 h = 21:00 = end) → single shifted slot at 21:00.
        let times = HydrationReminderScheduler.reminderTimes(
            start: TimeOfDay(rawMinutes: 540),
            end: TimeOfDay(rawMinutes: 1_260),
            intervalMinutes: 120,
            lastDrink: TimeOfDay(rawMinutes: 19 * 60)
        )
        #expect(times.map(\.rawMinutes) == [1_260])
    }
}
