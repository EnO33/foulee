import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Sober glance: today's steps and active minutes, read straight off the watch.
//! It never touches the phone, so it renders identically out of range.
(:glance)
class FouleeGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var metrics = DailySnapshot.readMetrics($.readActivityInfo());
        var stepsText = SnapshotFormat.steps(metrics[DailySnapshot.METRIC_STEPS]);
        var minutesText = SnapshotFormat.activeMinutes(metrics[DailySnapshot.METRIC_ACTIVE_MINUTES]);

        var font = Graphics.FONT_GLANCE;
        var lineHeight = dc.getFontHeight(font);
        var height = dc.getHeight();

        if (2 * lineHeight <= height) {
            var top = (height - 2 * lineHeight) / 2;
            dc.drawText(0, top, font, stepsText, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(0, top + lineHeight, font, minutesText, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.drawText(
                0,
                height / 2,
                font,
                stepsText + " · " + minutesText,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }
}
