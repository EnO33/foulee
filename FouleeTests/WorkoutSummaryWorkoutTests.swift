import Foundation
import HealthKit
import Testing
@testable import Foulee

/// `WorkoutSummary.init(workout:)` — the projection every résumé row and
/// detail sheet is drawn from.
///
/// Written for issue #223, which flipped one field's precedence: energy now
/// takes the workout's own `activeEnergyBurned` statistics first and Foulée's
/// `estimatedCalories` metadata only as a fallback. That is the single change
/// in #223 that touches how workouts *already in Santé* render, and nothing
/// asserted this initialiser at all — no test anywhere built a `WorkoutSummary`
/// from an `HKWorkout`.
///
/// The two fixtures below are the contract: a session Foulée wrote (metadata,
/// no energy samples — it deliberately writes none, they would double-count the
/// daily total) still shows exactly the figure it always showed, and a session
/// that carries a real measurement shows the measurement rather than an
/// estimate frozen in metadata forever.
@Suite("WorkoutSummary from HKWorkout")
struct WorkoutSummaryWorkoutTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)
    private static let end = start.addingTimeInterval(1_800)

    /// Builds a workout the way HealthKit hands one back.
    ///
    /// The initialiser is deprecated in favour of `HKWorkoutBuilder`, which
    /// needs an authorized `HKHealthStore` and therefore a device — this is the
    /// only way to get an `HKWorkout` with known statistics inside a test
    /// process, so the one deprecation warning it raises is deliberate.
    /// Silencing it by marking this function (or the suite) deprecated is not
    /// an option: Swift Testing refuses `@Test` on deprecated declarations.
    private func makeWorkout(
        energyKcal: Double?,
        distanceMeters: Double?,
        metadata: [String: Any]?,
        activityType: HKWorkoutActivityType = .walking
    ) -> HKWorkout {
        HKWorkout(
            activityType: activityType,
            start: Self.start,
            end: Self.end,
            workoutEvents: nil,
            totalEnergyBurned: energyKcal.map {
                HKQuantity(unit: .kilocalorie(), doubleValue: $0)
            },
            totalDistance: distanceMeters.map {
                HKQuantity(unit: .meter(), doubleValue: $0)
            },
            metadata: metadata
        )
    }

    @Test("A session Foulée wrote keeps showing its own figures")
    func fouleeWrittenSessionIsUnchanged() {
        // Exactly what `HealthKitClient.saveWorkout` persists: our three
        // metadata values and no samples at all. This is the regression guard
        // for "no history moves" — every walk already in Santé looks like this,
        // and reversing the precedence must not change what it renders.
        let workout = makeWorkout(
            energyKcal: nil,
            distanceMeters: nil,
            metadata: [
                FouleeWorkoutMetadata.steps: 5_000,
                FouleeWorkoutMetadata.distanceMeters: 3_600.0,
                FouleeWorkoutMetadata.calories: 200
            ]
        )
        let summary = WorkoutSummary(workout: workout)
        #expect(summary.activeCalories == 200)
        #expect(summary.steps == 5_000)
        #expect(summary.distanceKm == 3.6)
        #expect(summary.durationSeconds == 1_800)
    }

    @Test("A measured energy total beats our stored estimate")
    func measurementWinsOverMetadata() {
        // A session carrying both: real `activeEnergyBurned` statistics *and*
        // Foulée metadata. Nothing writes this today — the watch writes samples
        // and no metadata, the phone metadata and no samples — but the estimate
        // is the one the user would be stuck with forever if metadata won, and
        // a run does not burn a walk's kcal-per-step.
        let workout = makeWorkout(
            energyKcal: 137,
            distanceMeters: 4_000,
            metadata: [FouleeWorkoutMetadata.calories: 200]
        )
        let summary = WorkoutSummary(workout: workout)
        #expect(summary.activeCalories == 137)
        // Distance keeps the opposite order — metadata first — because ours is
        // not an estimate there: it is the pedometer distance for the session,
        // and #223 changed nothing about it.
        #expect(summary.distanceKm == 4)
    }

    @Test("A workout from another source falls back to its own statistics")
    func otherSourcesUseTheirStatistics() {
        // The Watch / Forme / Garmin shape: samples, no Foulée metadata.
        let workout = makeWorkout(energyKcal: 312, distanceMeters: 5_200, metadata: nil)
        let summary = WorkoutSummary(workout: workout)
        #expect(summary.activeCalories == 312)
        #expect(summary.distanceKm == 5.2)
        // No metadata means no step count — the detail sheet re-queries a
        // window for those.
        #expect(summary.steps == 0)
        #expect(summary.elevationMeters == 0)
    }

    @Test("Elevation comes from the standard metadata key")
    func elevationFromStandardMetadata() {
        let workout = makeWorkout(
            energyKcal: nil,
            distanceMeters: nil,
            metadata: [
                HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: 42)
            ]
        )
        #expect(WorkoutSummary(workout: workout).elevationMeters == 42)
    }
}

extension WorkoutSummaryWorkoutTests {
    /// The type was on the `HKWorkout` all along; issue #245 is that nothing
    /// read it. Asserted here rather than only on `RecordedActivity` because
    /// the mapping being right is useless if the projection drops it.
    @Test("The summary carries the type the workout was recorded with", arguments: [
        (HKWorkoutActivityType.walking, RecordedActivity.walking),
        (HKWorkoutActivityType.running, RecordedActivity.running),
        (HKWorkoutActivityType.hiking, RecordedActivity.hiking)
    ])
    func summaryCarriesTheActivity(
        type: HKWorkoutActivityType,
        expected: RecordedActivity
    ) {
        let workout = makeWorkout(
            energyKcal: 120,
            distanceMeters: 2_400,
            metadata: nil,
            activityType: type
        )
        #expect(WorkoutSummary(workout: workout).activity == expected)
    }
}
