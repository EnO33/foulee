import Toybox.Lang;
import Toybox.WatchUi;

//! The one session in progress, and the screens it puts on the stack: the
//! session's pages over the home, the pause menu over the pages.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module SessionFlow {

    var _recorder as SessionRecorder? = null;

    function start(running as Boolean) as Void {
        var recorder = new SessionRecorder(running);
        recorder.start();
        _recorder = recorder;
        var pages = new WatchUi.ViewLoop(new SessionPages(recorder), {:wrap => true});
        WatchUi.pushView(pages, new WatchUi.ViewLoopDelegate(pages), WatchUi.SLIDE_UP);
    }

    //! Saves the session into Garmin Connect and queues its summary for the
    //! phone, which shows the outing until Garmin Connect writes it to Santé
    //! (ADR 0009, D2). The outbox is tried at once; the background service
    //! retries what does not get through.
    function save(recorder as SessionRecorder) as Dictionary<Symbol, Number> {
        var summary = recorder.summary();
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

    //! Back to the home once the session is discarded: pops the pause menu,
    //! then the session's pages.
    function end() as Void {
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
}
