import Toybox.Lang;

//! The session's messages to the phone (ADR 0009, D6), each a complete record:
//!
//! - `summary` (D2): a saved session, as the phone needs it to show the outing
//!   before Garmin Connect writes it to Santé. A copy delivered twice is the
//!   same outing twice and the phone keeps one (its start time identifies it).
//! - `session` (D7): the session in progress, for the phone's mirror screen.
//!   A lost one is put right by the next.
//!
//! The keys are the contract with `GarminSessionSummary` and
//! `GarminSessionState` on the phone.
module SessionMessage {

    const SUMMARY_TYPE = "summary";
    const STATE_TYPE = "session";
    const SCHEMA_VERSION = 1;

    const SPORT_WALKING = "walking";
    const SPORT_RUNNING = "running";

    //! `summary` is `SessionRecorder.summary()`: seconds recorded (pauses
    //! excluded), metres, climb and descent in metres (`ascentM`, #536;
    //! `descentM`, #566: a phone that predates them ignores the keys), steps,
    //! heart rate, and the start and end
    //! instants in epoch seconds. `route` is `SessionRecorder.route()`, `RouteMath`'s flat
    //! fixed-point points, empty without a fix.
    function summary(
        summary as Dictionary<Symbol, Number>,
        running as Boolean,
        route as Array<Number>
    ) as Outbox.Message {
        return {
            "t" => SUMMARY_TYPE,
            "v" => SCHEMA_VERSION,
            "sport" => running ? SPORT_RUNNING : SPORT_WALKING,
            "start" => summary[:startedAt] as Number,
            "end" => summary[:endedAt] as Number,
            "duration" => summary[:seconds] as Number,
            "distanceM" => summary[:meters] as Number,
            "ascentM" => summary[:ascent] as Number,
            "descentM" => summary[:descent] as Number,
            "steps" => summary[:steps] as Number,
            "route" => route
        };
    }

    //! The session as it stands, read from `SessionRecorder.summary()`: its
    //! end instant is the moment it was read, the one the phone dates the
    //! figures with. A heart rate of 0 is none. `paused` and `ended` are 0 or
    //! 1, so the end fits the outbox like any other message.
    function state(
        summary as Dictionary<Symbol, Number>,
        running as Boolean,
        paused as Boolean,
        ended as Boolean
    ) as Outbox.Message {
        return {
            "t" => STATE_TYPE,
            "v" => SCHEMA_VERSION,
            "sport" => running ? SPORT_RUNNING : SPORT_WALKING,
            "sent" => summary[:endedAt] as Number,
            "elapsed" => summary[:seconds] as Number,
            "distanceM" => summary[:meters] as Number,
            "steps" => summary[:steps] as Number,
            "hr" => summary[:heartRate] as Number,
            "paused" => paused ? 1 : 0,
            "ended" => ended ? 1 : 0
        };
    }
}
