/// iOS widget kind strings, shared between the app and the widget extension so
/// an AppIntent can reload a single widget by kind instead of burning every
/// widget's refresh budget (mirrors `WatchComplicationKind` on the watch side).
enum WidgetKind {
    static let today = "com.eno33.foulee.todayWidget"
    static let stat = "com.eno33.foulee.statWidget"
    static let hydration = "com.eno33.foulee.hydrationWidget"

    /// Widgets showing today's counters — the only ones a Connect IQ snapshot
    /// can move (issue #189). The streak widget is deliberately absent: the
    /// overlay feeds the displayed counters, never the streak history.
    static let counters = [today, stat]
}
