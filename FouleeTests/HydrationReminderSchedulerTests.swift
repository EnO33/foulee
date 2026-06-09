import Testing
@testable import Foulee

@Suite struct HydrationReminderSchedulerTests {
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
}
