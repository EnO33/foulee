import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! How often the counters are re-read while the view is on screen. Nothing
//! else asks for a redraw: without it, the steps shown are those of the moment
//! the app opened, however far one walks with it open (#470).
const VIEW_REFRESH_MS = 5000;

//! The watch home, like `WatchTodayView` on the Apple Watch (ADR 0009, D4):
//! the streak the phone sent, then today's figures in their Foulée colours,
//! steps and minutes against the phone's goals.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class FouleeView extends WatchUi.View {

    //! Runs only while the view is shown, so it never outlives the screen.
    private var _refresh as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        var refresh = new Timer.Timer();
        refresh.start(method(:requestRefresh), $.VIEW_REFRESH_MS, true);
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

        var metrics = DailySnapshot.readMetrics($.readActivityInfo());
        var sync = PhoneSync.load();
        var stepsGoal = 0;
        var minutesGoal = 0;

        if (sync != null) {
            stepsGoal = sync["stepsGoal"] as Number;
            minutesGoal = sync["minutesGoal"] as Number;
            drawLine(dc, 20, Graphics.FONT_SMALL, MetricPalette.STREAK,
                HomeFormat.streak(sync["streak"] as Number), null);
        } else {
            // Never synced: a streak of zero would be a lie, so say where it
            // comes from instead.
            drawLine(dc, 14, Graphics.FONT_XTINY, MetricPalette.SECONDARY,
                WatchUi.loadResource($.Rez.Strings.SyncHintTop) as String, null);
            drawLine(dc, 24, Graphics.FONT_XTINY, MetricPalette.SECONDARY,
                WatchUi.loadResource($.Rez.Strings.SyncHintBottom) as String, null);
        }

        var steps = metrics[DailySnapshot.METRIC_STEPS];
        var minutes = metrics[DailySnapshot.METRIC_ACTIVE_MINUTES];
        drawLine(dc, 38, Graphics.FONT_TINY, MetricPalette.STEPS,
            HomeFormat.steps(steps, stepsGoal), HomeFormat.steps(steps, 0));
        drawLine(dc, 53, Graphics.FONT_TINY, MetricPalette.MINUTES,
            HomeFormat.minutes(minutes, minutesGoal), HomeFormat.minutes(minutes, 0));
        drawLine(dc, 68, Graphics.FONT_TINY, MetricPalette.DISTANCE,
            SnapshotFormat.distance(metrics[DailySnapshot.METRIC_DISTANCE_CM]), null);
        drawLine(dc, 83, Graphics.FONT_TINY, MetricPalette.CALORIES,
            SnapshotFormat.groupDigits(metrics[DailySnapshot.METRIC_CALORIES], SnapshotFormat.thousandsSeparator())
                + " " + WatchUi.loadResource($.Rez.Strings.UnitCalories),
            null);
    }

    //! One centred line at `percent` of the height. When `text` does not fit
    //! the dial at that height, `shorter` (the figure without its goal) is
    //! drawn instead.
    private function drawLine(
        dc as Dc,
        percent as Number,
        font as Graphics.FontType,
        color as Graphics.ColorType,
        text as String,
        shorter as String?
    ) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var y = height * percent / 100;
        var shown = text;
        if (shorter != null) {
            var available = HomeFormat.lineWidth(width, height, y, isRound()) * 90 / 100;
            if (dc.getTextWidthInPixels(text, font) > available) {
                shown = shorter;
            }
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y, font, shown, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function isRound() as Boolean {
        return System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND;
    }
}
