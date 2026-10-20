import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Sober glance: the streak and today's active minutes against their goal. The
//! phone's part is read from Storage, never asked for, so it renders the same
//! out of range.
(:glance)
class FouleeGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var metrics = DailySnapshot.readMetrics($.readActivityInfo());
        var minutes = metrics[DailySnapshot.METRIC_ACTIVE_MINUTES];
        var sync = PhoneSync.load();

        // The streak and the minutes against their goal, like the home; the
        // steps stand in for the streak until the phone has sent one.
        var topText = SnapshotFormat.steps(metrics[DailySnapshot.METRIC_STEPS]);
        var topColor = MetricPalette.STEPS;
        var minutesGoal = 0;
        if (sync != null) {
            topText = HomeFormat.streak(sync["streak"] as Number);
            topColor = MetricPalette.STREAK;
            minutesGoal = sync["minutesGoal"] as Number;
        }
        var bottomText = HomeFormat.minutes(minutes, minutesGoal);

        var font = Graphics.FONT_GLANCE;
        var lineHeight = dc.getFontHeight(font);
        var height = dc.getHeight();

        if (2 * lineHeight <= height) {
            var top = (height - 2 * lineHeight) / 2;
            dc.setColor(topColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, top, font, topText, Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(MetricPalette.MINUTES, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, top + lineHeight, font, bottomText, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                0,
                height / 2,
                font,
                topText + " · " + bottomText,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }
}
