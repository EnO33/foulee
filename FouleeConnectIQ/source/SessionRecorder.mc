import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.WatchUi;

//! The session's recording, and nothing else: the watch's own FIT recorder
//! does the measuring (ADR 0009, D2). Duration, distance and heart rate are
//! read back from `Activity.getActivityInfo()`, never recomputed here.
//!
//! The activity lands in Garmin Connect like any other, and Garmin Connect
//! writes it to Santé: Foulée on the watch keeps no outing of its own.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SessionRecorder {

    private var _session as ActivityRecording.Session?;
    private var _running as Boolean;
    private var _startSteps as Number = 0;

    function initialize(running as Boolean) {
        _running = running;
    }

    function isRunning() as Boolean {
        return _running;
    }

    //! Recording, as opposed to paused or finished.
    function isRecording() as Boolean {
        var session = _session;
        return session != null && session.isRecording();
    }

    function start() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        var name = _running ? $.Rez.Strings.SportRun : $.Rez.Strings.SportWalk;
        var session = ActivityRecording.createSession({
            :name => WatchUi.loadResource(name) as String,
            :sport => _running ? Activity.SPORT_RUNNING : Activity.SPORT_WALKING
        });
        session.start();
        _session = session;
        _startSteps = todaySteps();
    }

    //! Duration (s), distance (m) and steps of the session so far, for the
    //! summary. Read before `save`, while the recorder still holds them.
    function summary() as Dictionary<Symbol, Number> {
        var seconds = 0;
        var meters = 0;
        var info = Activity.getActivityInfo();
        if (info != null) {
            var timerTime = info.timerTime;
            if (timerTime != null) {
                seconds = timerTime / 1000;
            }
            var distance = info.elapsedDistance;
            if (distance != null) {
                meters = distance.toNumber();
            }
        }
        return {
            :seconds => seconds,
            :meters => meters,
            :steps => SessionMath.stepsBetween(_startSteps, todaySteps())
        };
    }

    private function todaySteps() as Number {
        return DailySnapshot.readMetrics($.readActivityInfo())[DailySnapshot.METRIC_STEPS];
    }

    function pause() as Void {
        var session = _session;
        if (session != null && session.isRecording()) {
            session.stop();
        }
    }

    function resume() as Void {
        var session = _session;
        if (session != null && !session.isRecording()) {
            session.start();
        }
    }

    //! Ends the session into Garmin Connect.
    function save() as Void {
        var session = _session;
        if (session != null) {
            pause();
            session.save();
        }
        release();
    }

    //! Ends the session without leaving a trace.
    function discard() as Void {
        var session = _session;
        if (session != null) {
            pause();
            session.discard();
        }
        release();
    }

    //! Positions only need to flow for the recorder to use them; nothing is
    //! kept from them here.
    function onPosition(info as Position.Info) as Void {
    }

    private function release() as Void {
        _session = null;
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        Sensor.setEnabledSensors([]);
    }
}
