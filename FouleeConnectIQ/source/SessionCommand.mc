import Toybox.Lang;

//! What the phone asks of the session in progress (ADR 0009, D7): « Arrêter
//! la séance » on its mirror screen. The keys are the contract with
//! `GarminSessionCommand` on the phone.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module SessionCommand {

    const MESSAGE_TYPE = "command";
    const SCHEMA_VERSION = 1;
    const ACTION_STOP = "stop";

    //! Whether `data` is the phone asking to end the session. Anything else,
    //! a newer version included, is not: a command misread would end a
    //! session nobody asked to end.
    function isStop(data as Object?) as Boolean {
        if (!(data instanceof Lang.Dictionary)) {
            return false;
        }
        var message = data as Dictionary<String, Object?>;
        return MESSAGE_TYPE.equals(message.get("t"))
            && SCHEMA_VERSION.equals(message.get("v"))
            && ACTION_STOP.equals(message.get("action"));
    }
}
