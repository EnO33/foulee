import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;

//! Messages for the phone that must arrive, not just be tried once: a session
//! summary (ADR 0009, D2), the end of a session (D7), a glass of water (D8). Each waits in Storage
//! until a transmit of it completes, oldest first, so a phone out of range or
//! an app closed in between loses nothing. The snapshot stays out of it: it is
//! a whole state, and the next one replaces it.
(:background)
module Outbox {

    const KEY_MESSAGES = "outbox";

    //! A few days of sessions (a summary and an end each) and glasses. Past it
    //! the oldest goes: a phone that has not been seen for that long is better
    //! served by Garmin Connect, which has every session anyway. A hundred
    //! bytes a message keeps the whole queue within a few kilobytes of Storage.
    const CAPACITY = 32;

    function enqueue(message as Dictionary<String, Number or String>) as Void {
        var messages = load();
        messages.add(message);
        if (messages.size() > CAPACITY) {
            messages = messages.slice(messages.size() - CAPACITY, null);
        }
        Storage.setValue(KEY_MESSAGES, messages as Storage.ValueType);
    }

    //! The message to send next, or null when everything got through.
    function peek() as Dictionary<String, Number or String>? {
        var messages = load();
        return messages.size() > 0 ? messages[0] : null;
    }

    //! Drops the message `peek` returned, once the phone has it. Messages are
    //! only ever added at the end, so the head is still that one.
    function dropHead() as Void {
        var messages = load();
        if (messages.size() > 0) {
            Storage.setValue(KEY_MESSAGES, messages.slice(1, null) as Storage.ValueType);
        }
    }

    function load() as Array<Dictionary<String, Number or String>> {
        var stored = Storage.getValue(KEY_MESSAGES);
        if (stored instanceof Lang.Array) {
            return stored as Array<Dictionary<String, Number or String>>;
        }
        return [] as Array<Dictionary<String, Number or String>>;
    }
}

//! Sends the outbox, oldest first, then runs `next` once the last transmit
//! completes or the first one fails: the background service goes on to its
//! snapshot, the open app has nothing more to do. Returns false when nothing
//! was sent, `next` then being the caller's to run.
(:background)
function deliverOutbox(next as (Method() as Void)?) as Boolean {
    var message = Outbox.peek();
    if (message == null || !(Toybox has :Communications) || !$.isPhoneReachable()) {
        return false;
    }
    try {
        Communications.transmit(message as Communications.TransmitType, null, new $.OutboxListener(next));
    } catch (ex) {
        return false;
    }
    return true;
}

(:background)
class OutboxListener extends Communications.ConnectionListener {
    private var _next as (Method() as Void)?;

    function initialize(next as (Method() as Void)?) {
        ConnectionListener.initialize();
        _next = next;
    }

    function onComplete() as Void {
        Outbox.dropHead();
        if (!$.deliverOutbox(_next)) {
            finish();
        }
    }

    function onError() as Void {
        finish();
    }

    private function finish() as Void {
        var next = _next;
        if (next != null) {
            next.invoke();
        }
    }
}
