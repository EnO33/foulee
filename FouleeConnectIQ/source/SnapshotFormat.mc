import Toybox.Lang;
import Toybox.WatchUi;

//! French formatting of the numbers shown on the watch. Kept arithmetic (no
//! string slicing) so it behaves the same on every family.
(:glance)
module SnapshotFormat {

    //! "12 345" — thousands separated by a space, as in French typography.
    function groupDigits(value as Number) as String {
        if (value < 1000) {
            return value.format("%d");
        }
        return groupDigits(value / 1000) + " " + (value % 1000).format("%03d");
    }

    //! "12 345 pas"
    function steps(count as Number) as String {
        return groupDigits(count) + " " + WatchUi.loadResource($.Rez.Strings.UnitSteps);
    }

    //! "42 min actives"
    function activeMinutes(minutes as Number) as String {
        return groupDigits(minutes) + " " + WatchUi.loadResource($.Rez.Strings.UnitActiveMinutes);
    }

    //! "3,4 km" — one decimal, French comma.
    function distance(centimeters as Number) as String {
        var meters = centimeters / 100;
        var kilometers = meters / 1000;
        var tenths = (meters % 1000) / 100;
        return kilometers.format("%d") + "," + tenths.format("%d")
            + " " + WatchUi.loadResource($.Rez.Strings.UnitKilometers);
    }
}
