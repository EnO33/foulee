import Toybox.Lang;
import Toybox.WatchUi;

//! The session's pages, swiped through like the Apple Watch's: Séance, then
//! Journée — the home's streak and goals, still within reach mid-session
//! (ADR 0009, D4). START, a tap or BACK pause on either page.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SessionPages extends WatchUi.ViewLoopFactory {

    private var _recorder as SessionRecorder;

    function initialize(recorder as SessionRecorder) {
        ViewLoopFactory.initialize();
        _recorder = recorder;
    }

    function getSize() as Number {
        return 2;
    }

    function getView(page as Number) as [WatchUi.View] or [WatchUi.View, WatchUi.BehaviorDelegate] {
        var view = page == 0 ? new SessionView(_recorder) : new FouleeView();
        return [view, new SessionDelegate(_recorder)];
    }
}
