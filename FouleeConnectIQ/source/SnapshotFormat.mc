import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Formatting of the numbers shown on the watch, in the watch's language: the
//! units come from the localized string resources, the separators from here
//! (a lone space would not survive a string resource). Kept arithmetic (no
//! string slicing) so it behaves the same on every family.
(:glance)
module SnapshotFormat {

    //! French typography on a French watch ("12 345", "3,4"), English
    //! everywhere else ("12,345", "3.4"), matching the strings the SDK picks.
    function isFrench() as Boolean {
        var settings = System.getDeviceSettings();
        if (settings has :systemLanguage) {
            return settings.systemLanguage == System.LANGUAGE_FRE;
        }
        return false;
    }

    function thousandsSeparator() as String {
        return isFrench() ? " " : ",";
    }

    function decimalSeparator() as String {
        return isFrench() ? "," : ".";
    }

    //! "12 345" with " ", "12,345" with ",".
    function groupDigits(value as Number, separator as String) as String {
        if (value < 1000) {
            return value.format("%d");
        }
        return groupDigits(value / 1000, separator) + separator + (value % 1000).format("%03d");
    }

    //! "3,4" with ",", "3.4" with "." — kilometres to one decimal, truncated.
    function kilometers(centimeters as Number, separator as String) as String {
        var meters = centimeters / 100;
        var tenths = (meters % 1000) / 100;
        return (meters / 1000).format("%d") + separator + tenths.format("%d");
    }

    //! "12 345 pas", "12,345 steps"
    function steps(count as Number) as String {
        return groupDigits(count, thousandsSeparator()) + " " + WatchUi.loadResource($.Rez.Strings.UnitSteps);
    }

    //! "42 min actives", "42 active min"
    function activeMinutes(minutes as Number) as String {
        return groupDigits(minutes, thousandsSeparator()) + " "
            + WatchUi.loadResource($.Rez.Strings.UnitActiveMinutes);
    }

    //! "3,4 km", "3.4 km"
    function distance(centimeters as Number) as String {
        return kilometers(centimeters, decimalSeparator()) + " "
            + WatchUi.loadResource($.Rez.Strings.UnitKilometers);
    }
}
