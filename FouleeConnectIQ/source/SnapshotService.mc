import Toybox.ActivityMonitor;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

//! Interval between two snapshots. Five minutes is the floor the system
//! enforces on temporal events.
(:background :glance)
const SNAPSHOT_PERIOD_SECONDS = 5 * 60;

//! Set once the service has called `Background.exit`, which may only happen
//! once per wake-up.
(:background)
var snapshotServiceEnded as Boolean = false;

//! Persistence of the snapshot state, shared by the foreground app and the
//! background service.
(:background :glance)
module SnapshotStore {

    const KEY_METRICS = "snapshotMetrics";
    const KEY_GENERATION = "snapshotGeneration";
    const KEY_DELIVERED_GENERATION = "snapshotDeliveredGeneration";

    //! Metrics of the last assembled snapshot, or null on a fresh install.
    function loadMetrics() as Array<Number>? {
        var stored = Storage.getValue(KEY_METRICS);
        if (stored instanceof Lang.Array && stored.size() == DailySnapshot.METRIC_COUNT) {
            return stored as Array<Number>;
        }
        return null;
    }

    function loadGeneration() as Number {
        return DailySnapshot.asCount(Storage.getValue(KEY_GENERATION));
    }

    //! -1 until a snapshot has actually reached the phone, so that generation 0
    //! is never mistaken for a delivered one.
    function loadDeliveredGeneration() as Number {
        var stored = Storage.getValue(KEY_DELIVERED_GENERATION);
        if (stored instanceof Lang.Number) {
            return stored;
        }
        return -1;
    }

    function save(metrics as Array<Number>, generation as Number) as Void {
        Storage.setValue(KEY_METRICS, metrics as Storage.ValueType);
        Storage.setValue(KEY_GENERATION, generation);
    }

    function markDelivered(generation as Number) as Void {
        Storage.setValue(KEY_DELIVERED_GENERATION, generation);
    }
}

//! Today's activity as reported by the device, or null when the family does not
//! expose the activity monitor at all.
(:background :glance)
function readActivityInfo() as ActivityInfoLike? {
    if (!(Toybox has :ActivityMonitor)) {
        return null;
    }
    // `ActivityMonitor.Info` satisfies the interface field by field; the cast
    // only tells the checker so, since it does not match structurally on its own.
    return ActivityMonitor.getInfo() as ActivityInfoLike;
}

//! Whether the phone is in range. A watch left on the nightstand is the normal
//! case, not a failure, so this is checked before spending any BLE budget.
(:background)
function isPhoneReachable() as Boolean {
    var settings = System.getDeviceSettings();
    if (settings has :phoneConnected) {
        return settings.phoneConnected;
    }
    // Unknown on this family: let the transmit itself decide.
    return true;
}

//! Ends the background wake-up exactly once.
(:background)
function endSnapshotService() as Void {
    if ($.snapshotServiceEnded) {
        return;
    }
    $.snapshotServiceEnded = true;
    Background.exit(null);
}

//! Reacts to the outcome of a transmit. Both outcomes are silent: a failure
//! simply means the same generation is retried at the next temporal event.
(:background)
class SnapshotConnectionListener extends Communications.ConnectionListener {
    private var _generation as Number;

    function initialize(generation as Number) {
        ConnectionListener.initialize();
        _generation = generation;
    }

    function onComplete() as Void {
        SnapshotStore.markDelivered(_generation);
        $.endSnapshotService();
    }

    function onError() as Void {
        $.endSnapshotService();
    }
}

//! Assembles the snapshot and pushes it to the phone when there is something
//! new to say and a phone to say it to.
(:background)
function publishSnapshot() as Void {
    var metrics = DailySnapshot.readMetrics($.readActivityInfo());
    var previous = SnapshotStore.loadMetrics();
    var generation = DailySnapshot.nextGeneration(metrics, previous, SnapshotStore.loadGeneration());
    var alreadyDelivered = (generation == SnapshotStore.loadDeliveredGeneration());
    SnapshotStore.save(metrics, generation);

    if (alreadyDelivered || !(Toybox has :Communications) || !$.isPhoneReachable()) {
        $.endSnapshotService();
        return;
    }

    var payload = DailySnapshot.makePayload(metrics, Time.now().value(), generation);
    try {
        Communications.transmit(
            payload as Communications.TransmitType,
            null,
            new $.SnapshotConnectionListener(generation)
        );
    } catch (ex) {
        $.endSnapshotService();
    }
}

//! Entry point of the background service.
(:background)
class SnapshotService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        $.publishSnapshot();
    }
}
