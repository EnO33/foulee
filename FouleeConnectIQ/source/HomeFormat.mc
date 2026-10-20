import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

//! What the home screen and the glance write next to the figures: progress
//! toward the phone's goals and the streak (ADR 0009, D4). The arithmetic is
//! kept free of any screen so the tests can pin it.
(:glance)
module HomeFormat {

    //! "8 421 / 10 000" toward a goal, the bare "8 421" without one: a goal of
    //! zero means the phone has not sent any yet.
    function progress(value as Number, goal as Number, separator as String) as String {
        var text = SnapshotFormat.groupDigits(value, separator);
        if (goal <= 0) {
            return text;
        }
        return text + " / " + SnapshotFormat.groupDigits(goal, separator);
    }

    //! "12 j de série", "12-day streak"
    function streak(days as Number) as String {
        return Lang.format(WatchUi.loadResource($.Rez.Strings.StreakDays) as String, [days]);
    }

    //! "8 421 / 10 000 pas", or "8 421 pas" before the first sync.
    function steps(value as Number, goal as Number) as String {
        return progress(value, goal, SnapshotFormat.thousandsSeparator()) + " "
            + WatchUi.loadResource($.Rez.Strings.UnitSteps);
    }

    //! "47 / 30 min", or "47 min actives" before the first sync.
    function minutes(value as Number, goal as Number) as String {
        if (goal <= 0) {
            return SnapshotFormat.activeMinutes(value);
        }
        return progress(value, goal, SnapshotFormat.thousandsSeparator()) + " "
            + WatchUi.loadResource($.Rez.Strings.UnitMinutes);
    }

    //! The width a line drawn at `y` can use: the chord of a round screen at
    //! that height, the full width of any other. Lets a line give up its goal
    //! rather than run off the edge of the dial.
    function lineWidth(width as Number, height as Number, y as Number, isRound as Boolean) as Number {
        if (!isRound) {
            return width;
        }
        var radius = width / 2.0;
        var offset = y - height / 2.0;
        var squared = radius * radius - offset * offset;
        if (squared <= 0) {
            return 0;
        }
        return (2 * Math.sqrt(squared)).toNumber();
    }
}
