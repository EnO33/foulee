import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Full-screen view: the same three numbers as the glance, nothing more. The
//! watch is a sensor for Foulée, not a second app.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class FouleeView extends WatchUi.View {

    function initialize() {
        View.initialize();
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
