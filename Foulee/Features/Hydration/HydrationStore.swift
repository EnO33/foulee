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

    /// Bumped on every refresh. A read that started earlier but finishes later
    /// (a slow HealthKit query) must NOT overwrite a newer value — otherwise a
    /// glass logged on the watch, or a fresh "J'ai bu" tap, gets clobbered by
    /// the refresh that fires when the app returns to the foreground. Only the
    /// most recent refresh is allowed to commit.
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var observerTask: Task<Void, Never>?

    /// Refresh whenever `dietaryWater` changes in Health — including water that
    /// synced in from the watch — so the card reflects the other device without
    /// the user reopening the app. Idempotent; safe to call on appear.
    func startObserving() {
        guard observerTask == nil else { return }
        let changes = healthKit.observeWaterChanges()
        observerTask = Task { [weak self] in
            for await _ in changes {
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let value = (try? await healthKit.todayWaterML()) ?? 0
        guard generation == refreshGeneration else { return }
        intakeML = value
        // Keep the hydration widget's ring in sync with what the app shows.
        SharedStore.updateWater(intakeML: value)
    }

    /// Called when the user turns hydration on: prompt for Health access (so
    /// `dietaryWater` can be written/read), then load today's intake.
    func enable() async {
        _ = try? await healthKit.requestAuthorization()
        await refresh()
    }

    /// Log one glass to Health, then re-read so the card reflects it. Surfaces
    /// the same confirmation toast as the notification action, and shifts the
    /// reminder grid so the next one lands a full interval after this glass.
    func logGlass(ml: Int) async {
        try? await healthKit.logWater(ml)
        await refresh()
        WidgetCenter.shared.reloadAllTimelines()
        HydrationNotification.confirm(kind: "drank", amount: ml)
        await HydrationReminderScheduler().recordDrinkAndReschedule()
    }
}
