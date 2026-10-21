import Toybox.Communications;
import Toybox.Lang;
import Toybox.Timer;

//! How often the session in progress is stated to the phone (ADR 0009, D7).
const SESSION_STATE_PERIOD_MS = 10000;

//! The session as the phone mirrors it (ADR 0009, D7): its complete state
//! every 10 s while the phone is in range, and at each pause and resume. These
//! go straight out, since a lost state is put right by the next one. The end
//! has no next one, so it waits in the outbox until the phone has it, or the
//! phone's screen would show the session forever.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SessionLink {

    private var _recorder as SessionRecorder;
    private var _timer as Timer.Timer;

    function initialize(recorder as SessionRecorder) {
        _recorder = recorder;
        _timer = new Timer.Timer();
        _timer.start(method(:send), $.SESSION_STATE_PERIOD_MS, true);
        send();
    }

    function send() as Void {
        if (!(Toybox has :Communications) || !$.isPhoneReachable()) {
            return;
        }
        try {
            Communications.transmit(state(false) as Communications.TransmitType, null, new $.SessionStateListener());
        } catch (ex) {
            // The next state replaces this one.
        }
    }

    //! Queues the end; read before the recorder saves or discards, while it
    //! still holds the figures. The caller delivers the outbox.
    function end() as Void {
        _timer.stop();
        Outbox.enqueue(state(true));
    }

    private function state(ended as Boolean) as Outbox.Message {
        return SessionMessage.state(_recorder.summary(), _recorder.isRunning(), !_recorder.isRecording(), ended);
    }
}

//! Nothing to do either way: a state that did not get through is replaced by
//! the next.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SessionStateListener extends Communications.ConnectionListener {

    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
    }

    function onError() as Void {
    }
}
