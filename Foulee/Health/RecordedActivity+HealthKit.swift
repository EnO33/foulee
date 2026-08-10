import HealthKit

extension RecordedActivity {
    /// Read `HKWorkout.workoutActivityType`.
    ///
    /// Total rather than optional, unlike `SessionActivity(_:)`: that one
    /// refuses to name a type Foulée does not record, because it feeds a
    /// *write* and a wrong stamp is permanent. This one feeds a label, and a
    /// session the app cannot classify still has to appear in the résumé — it
    /// happened, and hiding it would be a worse lie than calling it « Séance ».
    ///
    /// Separate file from the enum so `RecordedActivity` itself stays
    /// HealthKit-free, the same split `SessionActivity` / `SessionActivity+HealthKit`
    /// already uses.
    init(_ type: HKWorkoutActivityType) {
        switch type {
        case .walking: self = .walking
        case .running: self = .running
        case .hiking: self = .hiking
        default: self = .other
        }
    }
}
