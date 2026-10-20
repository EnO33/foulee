import Toybox.Lang;

//! The `summary` message (ADR 0009, D2, D6): a saved session, as the phone
//! needs it to show the outing before Garmin Connect writes it to Santé. A
//! complete record, so a copy delivered twice is the same outing twice and the
//! phone keeps one (its start time identifies it).
//!
//! The keys are the contract with `GarminSessionSummary` on the phone.
module SessionMessage {

    const MESSAGE_TYPE = "summary";
    const SCHEMA_VERSION = 1;

    const SPORT_WALKING = "walking";
    const SPORT_RUNNING = "running";

    //! `summary` is `SessionRecorder.summary()`: seconds recorded (pauses
    //! excluded), metres, steps, and the start and end instants in epoch
    //! seconds.
    function summary(summary as Dictionary<Symbol, Number>, running as Boolean) as Dictionary<String, Number or String> {
        return {
            "t" => MESSAGE_TYPE,
            "v" => SCHEMA_VERSION,
            "sport" => running ? SPORT_RUNNING : SPORT_WALKING,
            "start" => summary[:startedAt] as Number,
            "end" => summary[:endedAt] as Number,
            "duration" => summary[:seconds] as Number,
            "distanceM" => summary[:meters] as Number,
            "steps" => summary[:steps] as Number
        };
    }
}
