import Dependencies
import Observation
import WidgetKit

/// Today's water intake, backed by Apple Health (`dietaryWater`). The app never
/// asks for a typed amount: each "J'ai bu" logs one glass. Kept separate from
/// `TodayStore` so the hydration card refreshes independently.
@MainActor
@Observable
final class HydrationStore {
    @ObservationIgnored @Dependency(\.healthKit) private var healthKit

    private(set) var intakeML = 0

    func refresh() async {
        intakeML = (try? await healthKit.todayWaterML()) ?? 0
        // Keep the hydration widget's ring in sync with what the app shows.
        SharedStore.updateWater(intakeML: intakeML)
    }

    /// Called when the user turns hydration on: prompt for Health access (so
    /// `dietaryWater` can be written/read), then load today's intake.
    func enable() async {
        _ = try? await healthKit.requestAuthorization()
        await refresh()
    }

    /// Log one glass to Health, then re-read so the card reflects it. Surfaces
    /// the same confirmation toast as the notification action.
    func logGlass(ml: Int) async {
        try? await healthKit.logWater(ml)
        await refresh()
        WidgetCenter.shared.reloadAllTimelines()
        HydrationNotification.confirm(kind: "drank", amount: ml)
    }
}
