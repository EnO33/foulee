import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

//! How often the counters are re-read while the view is on screen. Nothing
//! else asks for a redraw: without it, the steps shown are those of the moment
//! the app opened, however far one walks with it open (#470).
const VIEW_REFRESH_MS = 5000;

//! Full-screen view: the same three numbers as the glance, nothing more. The
//! watch is a sensor for Foulée, not a second app.
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
        var centerX = dc.getWidth() / 2;
        var height = dc.getHeight();
        var centered = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.drawText(
            centerX,
            height * 20 / 100,
            Graphics.FONT_TINY,
            WatchUi.loadResource($.Rez.Strings.AppName) as String,
            centered
        );
        dc.drawText(
            centerX,
            height * 42 / 100,
            Graphics.FONT_MEDIUM,
            SnapshotFormat.steps(metrics[DailySnapshot.METRIC_STEPS]),
            centered
        );
        dc.drawText(
            centerX,
            height * 62 / 100,
            Graphics.FONT_SMALL,
            SnapshotFormat.activeMinutes(metrics[DailySnapshot.METRIC_ACTIVE_MINUTES]),
            centered
        );
        dc.drawText(
            centerX,
            height * 80 / 100,
            Graphics.FONT_TINY,
            SnapshotFormat.distance(metrics[DailySnapshot.METRIC_DISTANCE_CM]),
            centered
        );
    }
}
