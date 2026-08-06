import HealthKit

extension SessionActivity {
    /// The `HKWorkoutConfiguration.activityType` to stamp on the workout.
    ///
    /// The single place the app decides what Santé will show for a session.
    /// Both writers go through it — `HealthKitClient.saveWorkout` on the phone
    /// and `WatchWorkoutStore.beginSession` on the watch — so there is no
    /// activity literal left next to either builder (issue #223).
    ///
    /// Separate file from `SessionActivity` so the enum itself stays
    /// HealthKit-free, the same split `HealthKitClient` / `HealthKitClient+Live`
    /// already uses: the type travels through preferences, the sync payload and
    /// the walk model, none of which should drag the framework behind them.
    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .walking: .walking
        case .running: .running
        }
    }
}
