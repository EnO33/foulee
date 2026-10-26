import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! The end of a saved session, like the Apple Watch's recap: duration, steps,
//! distance, the climb and descent when the watch measured any (#536), and
//! « Terminer » back to the home.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SummaryView extends WatchUi.View {

    private var _summary as Dictionary<Symbol, Number>;

    function initialize(summary as Dictionary<Symbol, Number>) {
        View.initialize();
        _summary = summary;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centered = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var seconds = _summary[:seconds] as Number;
        var steps = _summary[:steps] as Number;
        var meters = _summary[:meters] as Number;
        var elevation = SessionMath.elevation(_summary[:ascent] as Number, _summary[:descent] as Number);
        // One more line when there is a climb: the figures move up to make
        // room, and a flat outing keeps the layout it always had.
        var stepsY = elevation != null ? 52 : 55;
        var distanceY = elevation != null ? 64 : 69;

        dc.setColor(MetricPalette.SECONDARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 18 / 100, Graphics.FONT_XTINY,
            WatchUi.loadResource($.Rez.Strings.SessionSaved) as String, centered);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 36 / 100, Graphics.FONT_NUMBER_MILD, SessionMath.clock(seconds), centered);
        dc.setColor(MetricPalette.STEPS, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * stepsY / 100, Graphics.FONT_SMALL, SnapshotFormat.steps(steps), centered);
        dc.setColor(MetricPalette.DISTANCE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * distanceY / 100, Graphics.FONT_SMALL, SnapshotFormat.distance(meters * 100), centered);
        if (elevation != null) {
            dc.setColor(MetricPalette.SECONDARY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 75 / 100, Graphics.FONT_XTINY, elevation, centered);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 85 / 100, Graphics.FONT_TINY,
            WatchUi.loadResource($.Rez.Strings.Done) as String, centered);
    }
}

//! « Terminer » — START, a tap or BACK — returns to the home.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SummaryDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
