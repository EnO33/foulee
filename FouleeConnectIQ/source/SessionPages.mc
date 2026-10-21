import Toybox.Lang;
import Toybox.WatchUi;

//! The session's pages, swiped through like the Apple Watch's: Séance, then
//! Journée — the home's streak and goals, still within reach mid-session —
//! then Plan on the watches with built-in maps (ADR 0009, D4). START, a tap or
//! BACK pause on every page.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SessionPages extends WatchUi.ViewLoopFactory {

    private var _recorder as SessionRecorder;

    function initialize(recorder as SessionRecorder) {
        ViewLoopFactory.initialize();
        _recorder = recorder;
    }

    function getSize() as Number {
        return (WatchUi has :MapTrackView) ? 3 : 2;
    }

    function getView(page as Number) as [WatchUi.ViewLoopFactory.Views] or [WatchUi.ViewLoopFactory.Views, WatchUi.ViewLoopFactory.Delegates] {
        var delegate = new SessionDelegate(_recorder);
        if (page == 0) {
            return [new SessionView(_recorder), delegate];
        }
        if (page == 1) {
            return [new FouleeView(), delegate];
        }
        return [new SessionMapView(_recorder), delegate];
    }
}
