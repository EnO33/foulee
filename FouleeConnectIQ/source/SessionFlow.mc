import Toybox.Lang;
import Toybox.WatchUi;

//! The one session in progress, and the screens it puts on the stack: the
//! Séance page over the home, the pause menu over the page.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module SessionFlow {

    var _recorder as SessionRecorder? = null;

    function start(running as Boolean) as Void {
        var recorder = new SessionRecorder(running);
        recorder.start();
        _recorder = recorder;
        WatchUi.pushView(new SessionView(recorder), new SessionDelegate(recorder), WatchUi.SLIDE_UP);
    }

    //! A saved session ends on its summary: the pause menu is popped and the
    //! Séance page replaced by the summary, which « Terminer » closes.
    function finish(summary as Dictionary<Symbol, Number>) as Void {
        _recorder = null;
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.switchToView(new SummaryView(summary), new SummaryDelegate(), WatchUi.SLIDE_UP);
    }

    //! Back to the home once the session is discarded: pops the pause menu,
    //! then the Séance page.
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
            recorder.save();
            _recorder = null;
        }
    }
}
