import WidgetKit

/// Feeds the Série complication. The streak is computed on the phone (the only
/// place with full history) and synced into the shared app group, so here we
/// just read that value — no HealthKit, no recompute. The watch app reloads
/// timelines whenever a fresh value arrives; this cadence is a fallback,
/// aligned with the iPhone widgets via WidgetRefresh so both move together.
struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: .now, streak: Self.syncedStreak()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entry = StreakEntry(date: .now, streak: Self.syncedStreak())
        completion(Timeline(entries: [entry], policy: .after(WidgetRefresh.nextRefresh(after: .now))))
    }

    private static func syncedStreak() -> Int {
        WatchSyncStore.read()?.streak ?? 0
    }
}
