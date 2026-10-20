import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! Foulée on the watch, like on the Apple Watch: the day at a glance, a
//! session started from the wrist, and today's numbers pushed to the iPhone
//! (ADR 0009). Nothing here needs the phone to be in range.
(:background :glance)
class FouleeApp extends Application.AppBase {

    //! True only in the process that showed the views: the background service
    //! starts and stops the same class, without any session code loaded.
    private var _hasViews as Boolean = false;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        scheduleSnapshots();
    }

    (:typecheck([disableBackgroundCheck, disableGlanceCheck]))
    function onStop(state as Dictionary?) as Void {
        if (_hasViews) {
            SessionFlow.saveIfOpen();
        }
    }

    (:typecheck([disableBackgroundCheck, disableGlanceCheck]))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        _hasViews = true;
        listenToPhone();
        return [new $.FouleeView(), new $.HomeDelegate()];
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
