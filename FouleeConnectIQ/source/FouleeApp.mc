import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! Foulée on the watch is a sensor, not a second app: it shows today's numbers
//! and pushes them to the iPhone. Nothing here needs the phone to be in range.
(:background :glance)
class FouleeApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        scheduleSnapshots();
    }

    function onStop(state as Dictionary?) as Void {
    }

    (:typecheck([disableBackgroundCheck, disableGlanceCheck]))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new $.FouleeView()];
    }

    (:glance :typecheck(disableBackgroundCheck))
    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new $.FouleeGlanceView()];
    }

    (:typecheck(disableGlanceCheck))
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new $.SnapshotService()];
    }

    //! Registers the recurring wake-up once. Re-registering on every launch
    //! would reset the schedule, so the existing registration wins.
    private function scheduleSnapshots() as Void {
        if (!(Toybox has :Background)) {
            return;
        }
        if (Background.getTemporalEventRegisteredTime() != null) {
            return;
        }
        try {
            Background.registerForTemporalEvent(new Time.Duration($.SNAPSHOT_PERIOD_SECONDS));
        } catch (ex instanceof Background.InvalidBackgroundTimeException) {
            // The system refused this slot; the next launch tries again.
        }
    }
}
