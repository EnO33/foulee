import Toybox.Lang;
import Toybox.Test;

//! Stand-in for `ActivityMonitor.ActiveMinutes`, which cannot be instantiated.
(:test)
class FakeActiveMinutes {
    public var total as Number;
    public var vigorous as Number;

    public function initialize(totalMinutes as Number, vigorousMinutes as Number) {
        total = totalMinutes;
        vigorous = vigorousMinutes;
    }
}

//! Stand-in for `ActivityMonitor.Info`: exposes every field the snapshot reads.
(:test)
class FakeActivityInfo {
    public var steps as Number?;
    public var distance as Number?;
    public var calories as Number?;
    public var activeMinutesDay as ActiveMinutesLike?;

    public function initialize() {
    }
}

//! Stand-in for a family that reports nothing but steps: the other symbols are
//! simply absent, which is what `has` checks are there for.
(:test)
class FakeStepsOnlyInfo {
    public var steps as Number?;

    public function initialize(stepCount as Number?) {
        steps = stepCount;
    }
}

(:test)
function snapshotUsesEveryInjectedField(logger as Logger) as Boolean {
    var info = new FakeActivityInfo();
    info.steps = 8421;
    info.distance = 634000;
    info.calories = 2103;
    info.activeMinutesDay = new FakeActiveMinutes(47, 12);

    var payload = DailySnapshot.makePayload(DailySnapshot.readMetrics(info), 1754380800, 7);
    logger.debug("payload = " + payload.toString());

    // A missing key reads as null, which never equals the expected Number, so
    // a renamed field fails here rather than slipping through.
    Test.assertEqual(payload["v"] as Object, DailySnapshot.SCHEMA_VERSION);
    Test.assertEqual(payload["steps"] as Object, 8421);
    Test.assertEqual(payload["distanceCm"] as Object, 634000);
    Test.assertEqual(payload["activeMinutes"] as Object, 47);
    Test.assertEqual(payload["activeMinutesVigorous"] as Object, 12);
    Test.assertEqual(payload["calories"] as Object, 2103);
    Test.assertEqual(payload["ts"] as Object, 1754380800);
    Test.assertEqual(payload["gen"] as Object, 7);
    Test.assertEqual(payload.size(), 8);
    return true;
}

(:test)
function snapshotSurvivesNullAndMissingFields(logger as Logger) as Boolean {
    var partial = new FakeActivityInfo();
    partial.steps = 1200;
    // distance, calories and activeMinutesDay stay null.
    var fromPartial = DailySnapshot.readMetrics(partial);
    Test.assertEqual(fromPartial[DailySnapshot.METRIC_STEPS], 1200);
    Test.assertEqual(fromPartial[DailySnapshot.METRIC_DISTANCE_CM], 0);
    Test.assertEqual(fromPartial[DailySnapshot.METRIC_ACTIVE_MINUTES], 0);
    Test.assertEqual(fromPartial[DailySnapshot.METRIC_ACTIVE_MINUTES_VIGOROUS], 0);
    Test.assertEqual(fromPartial[DailySnapshot.METRIC_CALORIES], 0);

    // A family that does not even declare the symbols. The cast is what a
    // pre-2.1.0 `ActivityMonitor.Info` amounts to at runtime.
    var stepsOnly = DailySnapshot.readMetrics(new FakeStepsOnlyInfo(310) as ActivityInfoLike);
    Test.assertEqual(stepsOnly[DailySnapshot.METRIC_STEPS], 310);
    Test.assertEqual(stepsOnly[DailySnapshot.METRIC_CALORIES], 0);

    // No activity monitor at all.
    var none = DailySnapshot.readMetrics(null);
    Test.assertEqual(none.size(), DailySnapshot.METRIC_COUNT);
    Test.assertEqual(none[DailySnapshot.METRIC_STEPS], 0);

    logger.debug("partial/stepsOnly/none handled without throwing");
    return true;
}

(:test)
function generationOnlyMovesWhenMetricsChange(logger as Logger) as Boolean {
    var first = [1000, 50000, 10, 2, 300];
    var same = [1000, 50000, 10, 2, 300];
    var moved = [1001, 50000, 10, 2, 300];

    // Nothing stored yet: first snapshot of the install.
    Test.assertEqual(DailySnapshot.nextGeneration(first, null, 0), 1);
    // A retry after a failed transmit reuses the very same generation.
    Test.assertEqual(DailySnapshot.nextGeneration(same, first, 4), 4);
    // Real movement bumps it.
    Test.assertEqual(DailySnapshot.nextGeneration(moved, first, 4), 5);

    logger.debug("generation is stable across retries");
    return true;
}

(:test)
function countsAreCoercedToNonNegativeNumbers(logger as Logger) as Boolean {
    Test.assertEqual(DailySnapshot.asCount(42), 42);
    Test.assertEqual(DailySnapshot.asCount(null), 0);
    Test.assertEqual(DailySnapshot.asCount(-3), 0);
    Test.assertEqual(DailySnapshot.asCount(12.9), 12);
    Test.assertEqual(DailySnapshot.asCount("nope"), 0);

    logger.debug("asCount is total");
    return true;
}

(:test)
function frenchFormattingIsReadable(logger as Logger) as Boolean {
    Test.assertEqual(SnapshotFormat.groupDigits(0), "0");
    Test.assertEqual(SnapshotFormat.groupDigits(999), "999");
    Test.assertEqual(SnapshotFormat.groupDigits(1000), "1 000");
    Test.assertEqual(SnapshotFormat.groupDigits(12345), "12 345");
    Test.assertEqual(SnapshotFormat.groupDigits(1234567), "1 234 567");

    logger.debug("digit grouping ok");
    return true;
}
