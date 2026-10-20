import Toybox.Lang;
import Toybox.WatchUi;

//! The one session in progress, and the screens it puts on the stack: the
//! session's pages over the home, the pause menu over the pages.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module SessionFlow {

    var _recorder as SessionRecorder? = null;
    var _link as SessionLink? = null;

    function start(running as Boolean) as Void {
        var recorder = new SessionRecorder(running);
        recorder.start();
        _recorder = recorder;
        _link = new SessionLink(recorder);
        var pages = new WatchUi.ViewLoop(new SessionPages(recorder), {:wrap => true});
        WatchUi.pushView(pages, new WatchUi.ViewLoopDelegate(pages), WatchUi.SLIDE_UP);
    }

    //! The session was paused or resumed: the phone's mirror says so at once
    //! rather than at the next periodic state (ADR 0009, D7).
    function stateChanged() as Void {
        var link = _link;
        if (link != null) {
            link.send();
        }
    }

    //! Saves the session into Garmin Connect and queues its end and its
    //! summary for the phone, which shows the outing until Garmin Connect
    //! writes it to Santé (ADR 0009, D2, D7). The outbox is tried at once; the
    //! background service retries what does not get through.
    function save(recorder as SessionRecorder) as Dictionary<Symbol, Number> {
        var summary = recorder.summary();
        endLink();
        recorder.save();
        Outbox.enqueue(SessionMessage.summary(summary, recorder.isRunning()));
        $.deliverOutbox(null);
        return summary;
    }

    //! A saved session ends on its summary: the pause menu is popped and the
    //! session's pages replaced by the summary, which « Terminer » closes.
    function finish(summary as Dictionary<Symbol, Number>) as Void {
        _recorder = null;
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.switchToView(new SummaryView(summary), new SummaryDelegate(), WatchUi.SLIDE_UP);
    }

    //! Discards the session, tells the phone it is over, and goes back to the
    //! home: pops the pause menu, then the session's pages.
    function discard(recorder as SessionRecorder) as Void {
        endLink();
        recorder.discard();
        $.deliverOutbox(null);
        _recorder = null;
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    //! The app is closing with a session still open: keep what was walked
    //! rather than lose it.
    function saveIfOpen() as Void {
        var recorder = _recorder;
        if (recorder != null) {
            save(recorder);
            _recorder = null;
        }
    }

    //! Queues the session's end for the phone's mirror, once.
    function endLink() as Void {
        var link = _link;
        if (link != null) {
            link.end();
        }
        _link = null;
    }
}
