import Toybox.Lang;

//! Structural view of `ActivityMonitor.ActiveMinutes`. Declaring it as an
//! interface lets the tests inject a stub, since the SDK class cannot be
//! instantiated outside the runtime.
(:background :glance)
typedef ActiveMinutesLike as interface {
    var total as Lang.Number;
    var vigorous as Lang.Number;
};

//! Structural view of `ActivityMonitor.Info`, restricted to the fields the
//! snapshot needs. Every one of them is optional on purpose: device families
//! differ, and the SDK documents that any field may be null.
(:background :glance)
typedef ActivityInfoLike as interface {
    var steps as Lang.Number or Null;
    var distance as Lang.Number or Null;
    var calories as Lang.Number or Null;
    var activeMinutesDay as ActiveMinutesLike or Null;
};

//! Assembly of the daily snapshot pushed to the iPhone.
//!
//! Everything here is pure: reading the device, persisting state and talking to
//! the phone all live in `SnapshotService`. That keeps the part which is easy to
//! get wrong small, obvious and unit testable.
(:background :glance)
module DailySnapshot {

    //! Payload schema version. Bump it whenever the shape changes.
    const SCHEMA_VERSION = 1;

    //! Indexes inside the metric tuple.
    enum Metric {
        METRIC_STEPS = 0,
        METRIC_DISTANCE_CM = 1,
        METRIC_ACTIVE_MINUTES = 2,
        METRIC_ACTIVE_MINUTES_VIGOROUS = 3,
        METRIC_CALORIES = 4
    }

    const METRIC_COUNT = 5;

    //! Reads the metrics off an `ActivityMonitor.Info` (or a stub). Missing
    //! symbols, null values and unexpected types all collapse to zero rather
    //! than throwing: an out-of-date family must still produce a snapshot.
    function readMetrics(info as ActivityInfoLike?) as Array<Number> {
        var metrics = [0, 0, 0, 0, 0];
        if (info == null) {
            return metrics;
        }

        // A field reached through `has` is untyped as far as the checker is
        // concerned, hence the casts; `asCount` is what actually validates it.
        if (info has :steps) {
            metrics[METRIC_STEPS] = asCount(info.steps as Object?);
        }
        if (info has :distance) {
            metrics[METRIC_DISTANCE_CM] = asCount(info.distance as Object?);
        }
        if (info has :calories) {
            metrics[METRIC_CALORIES] = asCount(info.calories as Object?);
        }
        if (info has :activeMinutesDay) {
            var active = info.activeMinutesDay;
            if (active != null) {
                if (active has :total) {
                    metrics[METRIC_ACTIVE_MINUTES] = asCount(active.total as Object?);
                }
                if (active has :vigorous) {
                    metrics[METRIC_ACTIVE_MINUTES_VIGOROUS] = asCount(active.vigorous as Object?);
                }
            }
        }

        return metrics;
    }

    //! Builds the transmitted dictionary. Keys stay short and values stay
    //! integers: the BLE link runs at roughly 1 KB/s.
    function makePayload(
        metrics as Array<Number>,
        timestamp as Number,
        generation as Number
    ) as Dictionary<String, Number> {
        return {
            "v" => SCHEMA_VERSION,
            "steps" => metrics[METRIC_STEPS],
            "distanceCm" => metrics[METRIC_DISTANCE_CM],
            "activeMinutes" => metrics[METRIC_ACTIVE_MINUTES],
            "activeMinutesVigorous" => metrics[METRIC_ACTIVE_MINUTES_VIGOROUS],
            "calories" => metrics[METRIC_CALORIES],
            "ts" => timestamp,
            "gen" => generation
        };
    }

    //! The generation only moves when the metrics actually change. A snapshot
    //! that failed to reach the phone is therefore retried under the very same
    //! generation, and the phone can drop a generation it already ingested.
    function nextGeneration(
        metrics as Array<Number>,
        previous as Array<Number>?,
        previousGeneration as Number
    ) as Number {
        if (sameMetrics(metrics, previous)) {
            return previousGeneration;
        }
        var next = previousGeneration + 1;
        // Stay inside the 32-bit signed range a Number can hold.
        if (next < 0) {
            return 0;
        }
        return next;
    }

    //! True when both metric tuples carry the same values.
    function sameMetrics(metrics as Array<Number>, previous as Array<Number>?) as Boolean {
        if (previous == null || previous.size() != metrics.size()) {
            return false;
        }
        for (var i = 0; i < metrics.size(); i += 1) {
            if (metrics[i] != previous[i]) {
                return false;
            }
        }
        return true;
    }

    //! Coerces an unknown value into a non-negative counter: whatever a device
    //! family or the object store happens to hold for a metric.
    function asCount(value as Object?) as Number {
        if (value instanceof Lang.Number) {
            return value < 0 ? 0 : value;
        }
        if (value instanceof Lang.Float || value instanceof Lang.Double) {
            var rounded = value.toNumber();
            return rounded < 0 ? 0 : rounded;
        }
        if (value instanceof Lang.Long) {
            var narrowed = value.toNumber();
            return narrowed < 0 ? 0 : narrowed;
        }
        return 0;
    }
}
