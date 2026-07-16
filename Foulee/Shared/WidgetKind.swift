/// iOS widget kind strings, shared between the app and the widget extension so
/// an AppIntent can reload a single widget by kind instead of burning every
/// widget's refresh budget (mirrors `WatchComplicationKind` on the watch side).
enum WidgetKind {
    static let hydration = "com.eno33.foulee.hydrationWidget"
}
