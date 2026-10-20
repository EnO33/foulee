import Toybox.Activity;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! How long the kilometre just completed stays over the figures.
const KILOMETER_ALERT_MS = 4000;

//! The Séance page: clock, distance, pace of the moment, heart rate, like the
//! Apple Watch's session (ADR 0009, D4). START pauses.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SessionView extends WatchUi.View {

    private var _recorder as SessionRecorder;
    private var _refresh as Timer.Timer?;
    private var _lastMeters as Number = 0;
    private var _alertKilometer as Number = 0;
    private var _alertUntil as Number = 0;

    function initialize(recorder as SessionRecorder) {
        View.initialize();
        _recorder = recorder;
    }

    function onShow() as Void {
        var refresh = new Timer.Timer();
        refresh.start(method(:requestRefresh), 1000, true);
        _refresh = refresh;
    }

    function onHide() as Void {
        var refresh = _refresh;
        if (refresh != null) {
            refresh.stop();
        }
        _refresh = null;
    }

    function requestRefresh() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var info = Activity.getActivityInfo();
        var seconds = 0;
        var meters = 0;
        var speed as Float? = null;
        var heartRate as Number? = null;
        if (info != null) {
            var timerTime = info.timerTime;
            if (timerTime != null) {
                seconds = timerTime / 1000;
            }
            var distance = info.elapsedDistance;
            if (distance != null) {
                meters = distance.toNumber();
            }
            speed = info.currentSpeed;
            heartRate = info.currentHeartRate;
        }
        noteKilometer(meters);

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centered = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        if (System.getTimer() < _alertUntil) {
            dc.setColor(MetricPalette.DISTANCE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2, Graphics.FONT_LARGE,
                Lang.format(WatchUi.loadResource($.Rez.Strings.KilometerDone) as String, [_alertKilometer]),
                centered);
            return;
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 30 / 100, Graphics.FONT_NUMBER_MEDIUM, SessionMath.clock(seconds), centered);
        dc.setColor(MetricPalette.DISTANCE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 52 / 100, Graphics.FONT_SMALL, SnapshotFormat.distance(meters * 100), centered);

        var pace = SessionMath.livePace(speed, _recorder.isRunning());
        dc.setColor(MetricPalette.STEPS, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 67 / 100, Graphics.FONT_SMALL, pace != null ? pace : "--", centered);

        dc.setColor(MetricPalette.HEART_RATE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 82 / 100, Graphics.FONT_SMALL,
            heartRate != null ? heartRate.format("%d") + " bpm" : "-- bpm", centered);
    }

    //! Vibrates and shows the kilometre for a few seconds when one is
    //! completed (the Apple Watch's alert, #382).
    private function noteKilometer(meters as Number) as Void {
        var kilometer = SessionMath.kilometerCrossed(_lastMeters, meters);
        _lastMeters = meters;
        if (kilometer == 0) {
            return;
        }
        _alertKilometer = kilometer;
        _alertUntil = System.getTimer() + $.KILOMETER_ALERT_MS;
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, 400)]);
        }
    }
}
