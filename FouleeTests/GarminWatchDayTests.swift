import FouleeKit
import Foundation
import Testing

/// Which day a v2 snapshot counts for (#473). The watch's counters reset at
/// its own midnight: when watch and phone sit in different time zones, the
/// phone's clock alone would file them on the wrong day.
@Suite("Garmin snapshot, watch's own day")
struct GarminWatchDayTests {
    private let calendar = Calendar.current

    /// Local noon today — far from both midnight boundaries.
    private var now: Date { calendar.startOfDay(for: .now).addingTimeInterval(12 * 60 * 60) }

    /// A v2 snapshot taken `minutesAgo` before `at`, on a watch whose own day
    /// began `watchDayBegan` seconds before `at`.
    private func watchSnapshot(at: Date, watchDayBegan: TimeInterval, minutesAgo: Double = 3) -> GarminDailySnapshot {
        GarminDailySnapshot(
            steps: 9_000, distanceCm: 600_000, activeMinutes: 50, activeMinutesVigorous: 0, calories: 0,
            timestamp: at.addingTimeInterval(-minutesAgo * 60),
            watchDayStart: at.addingTimeInterval(-watchDayBegan),
            generation: 3
        )
    }

    @Test("A v2 snapshot on the phone's own day counts, as v1 does")
    func watchDaySameZone() {
        let snapshot = watchSnapshot(at: now, watchDayBegan: now.timeIntervalSince(calendar.startOfDay(for: now)))
        #expect(GarminSnapshotOverlay.usability(snapshot, now: now, calendar: calendar) == .usable)
    }

    @Test("A watch already on tomorrow does not speak for the phone's today")
    func watchAheadOnTomorrow() {
        // 20:00 on the phone, 06:00 the next morning on a watch ten hours
        // ahead: its counters are six hours of a day the phone hasn't reached.
        let evening = calendar.startOfDay(for: now).addingTimeInterval(20 * 60 * 60)
        let snapshot = watchSnapshot(at: evening, watchDayBegan: 6 * 60 * 60)
        #expect(GarminSnapshotOverlay.usability(snapshot, now: evening, calendar: calendar) == .otherDay)
    }

    @Test("A watch still on yesterday does not speak for the phone's today")
    func watchBehindOnYesterday() {
        // 00:30 on the phone, 15:30 the day before on a watch nine hours
        // behind: the timestamp is today on the phone, the counters are not.
        let earlyMorning = calendar.startOfDay(for: now).addingTimeInterval(30 * 60)
        let snapshot = watchSnapshot(at: earlyMorning, watchDayBegan: 15.5 * 60 * 60)
        #expect(GarminSnapshotOverlay.usability(snapshot, now: earlyMorning, calendar: calendar) == .otherDay)
    }

    @Test("A watch a few hours off but on the same date still counts")
    func watchOffsetSameDate() {
        // Noon on the phone, 15:00 on a watch three hours ahead: same date.
        let snapshot = watchSnapshot(at: now, watchDayBegan: 15 * 60 * 60)
        #expect(GarminSnapshotOverlay.usability(snapshot, now: now, calendar: calendar) == .usable)
    }
}
