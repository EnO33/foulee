import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
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
        listenToPhone();
        return [new $.FouleeView()];
    }

    //! The phone's state arrives while the app is open (ADR 0009, D5). Only the
    //! full app listens: neither the glance nor the background service does.
    (:typecheck([disableBackgroundCheck, disableGlanceCheck]))
    private function listenToPhone() as Void {
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        }
    }

    (:typecheck([disableBackgroundCheck, disableGlanceCheck]))
    function onPhoneMessage(message as Communications.PhoneAppMessage) as Void {
        var state = PhoneSync.decode(message.data);
        if (state != null) {
            PhoneSync.save(state);
            WatchUi.requestUpdate();
        }
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
