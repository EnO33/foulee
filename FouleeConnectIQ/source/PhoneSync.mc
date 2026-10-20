import Toybox.Application.Storage;
import Toybox.Lang;

//! What the iPhone sends: the streak, the goals, the activity mode and the
//! hydration settings, which only the phone computes (ADR 0009, D5). Kept in
//! Storage, so the last state still shows with the phone out of range.
//!
//! The keys are the contract with `GarminPhoneSync` on the phone, pinned by
//! tests on both sides.
module PhoneSync {

    const MESSAGE_TYPE = "sync";
    const SCHEMA_VERSION = 1;
    const KEY_STATE = "phoneSync";

    const MODE_WALKING = "walking";

    //! The synced state, decoded leniently: null when the message is not a sync
    //! message this build understands (another type, a newer version), so a
    //! newer phone app never leaves a half-read state behind. Inside a message
    //! that is understood, a missing or mistyped field falls back to zero,
    //! false or walking, as the phone's own decoder does for the watch.
    function decode(data as Object?) as Dictionary<String, Number or Boolean or String>? {
        if (!(data instanceof Lang.Dictionary)) {
            return null;
        }
        var message = data as Dictionary;
        if (!MESSAGE_TYPE.equals(message.get("t")) || !SCHEMA_VERSION.equals(message.get("v"))) {
            return null;
        }
        return {
            "streak" => DailySnapshot.asCount(message.get("streak")),
            "minutesGoal" => DailySnapshot.asCount(message.get("minutesGoal")),
            "stepsGoal" => DailySnapshot.asCount(message.get("stepsGoal")),
            "mode" => asMode(message.get("mode")),
            "water" => asFlag(message.get("water")),
            "waterGoalML" => DailySnapshot.asCount(message.get("waterGoalML")),
            "glassML" => DailySnapshot.asCount(message.get("glassML"))
        };
    }

    function save(state as Dictionary<String, Number or Boolean or String>) as Void {
        Storage.setValue(KEY_STATE, state as Storage.ValueType);
    }

    //! The last state the phone sent, or null before the first one: the watch
    //! then says so instead of showing a streak of zero.
    function load() as Dictionary<String, Number or Boolean or String>? {
        var stored = Storage.getValue(KEY_STATE);
        if (stored instanceof Lang.Dictionary) {
            return stored as Dictionary<String, Number or Boolean or String>;
        }
        return null;
    }

    //! "walking", "running" or "both"; anything else is walking, the phone's
    //! own default (`ActivityMode`).
    function asMode(value as Object?) as String {
        if (value instanceof Lang.String && ("running".equals(value) || "both".equals(value))) {
            return value;
        }
        return MODE_WALKING;
    }

    function asFlag(value as Object?) as Boolean {
        if (value instanceof Lang.Boolean) {
            return value;
        }
        return false;
    }
}
