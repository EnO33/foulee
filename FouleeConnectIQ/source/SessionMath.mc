import Toybox.Lang;
import Toybox.Math;

//! The arithmetic of a session, apart from any screen or sensor (ADR 0009,
//! D9): the clock, the pace and the kilometre alert, stated the way the Apple
//! Watch states them (`WalkFormatting.swift`, `WatchWorkoutStore+Pace.swift`).
module SessionMath {

    //! Under 50 m a pace is the division amplifying a distance estimate into a
    //! figure that looks precise and is not (#276).
    const PACE_MIN_METERS = 50;

    //! Slower than 99 min/km is a pause someone forgot to end, not a pace.
    const PACE_MAX_SECONDS_PER_KM = 99 * 60;

    //! Live paces are rounded: 5 s/km running, 10 s/km walking (#300).
    const LIVE_PACE_STEP_RUNNING = 5;
    const LIVE_PACE_STEP_WALKING = 10;

    //! "07:42", or "1:02:05" past the hour.
    function clock(seconds as Number) as String {
        var hours = seconds / 3600;
        var minutes = (seconds % 3600) / 60;
        var rest = seconds % 60;
        if (hours > 0) {
            return Lang.format("$1$:$2$:$3$", [hours, minutes.format("%02d"), rest.format("%02d")]);
        }
        return Lang.format("$1$:$2$", [minutes.format("%02d"), rest.format("%02d")]);
    }

    //! "6'10\"/km" for a whole stretch, or null when it says nothing.
    function pace(seconds as Number, meters as Number) as String? {
        if (meters < PACE_MIN_METERS || seconds <= 0) {
            return null;
        }
        var secondsPerKm = seconds * 1000 / meters;
        if (secondsPerKm >= PACE_MAX_SECONDS_PER_KM) {
            return null;
        }
        return paceText(secondsPerKm);
    }

    //! The pace of the moment from the watch's current speed (m/s), rounded
    //! to the sport's step, or null standing still.
    function livePace(metersPerSecond as Float?, running as Boolean) as String? {
        if (metersPerSecond == null || metersPerSecond <= 0) {
            return null;
        }
        var secondsPerKm = 1000 / metersPerSecond;
        if (secondsPerKm >= PACE_MAX_SECONDS_PER_KM) {
            return null;
        }
        var step = running ? LIVE_PACE_STEP_RUNNING : LIVE_PACE_STEP_WALKING;
        return paceText((Math.round(secondsPerKm / step) * step).toNumber());
    }

    function paceText(secondsPerKm as Number) as String {
        return Lang.format("$1$'$2$\"/km", [secondsPerKm / 60, (secondsPerKm % 60).format("%02d")]);
    }

    //! The kilometre just completed between two readings of the distance, or
    //! 0 when none was. Only the last boundary counts: a reading that skips
    //! two (a GPS jump) alerts once, for where the wearer actually is.
    function kilometerCrossed(previousMeters as Number, meters as Number) as Number {
        var before = previousMeters / 1000;
        var now = meters / 1000;
        return now > before ? now : 0;
    }

    //! The steps taken during the session, from the day's counter read at the
    //! start and at the end. The counter restarts at midnight: a session that
    //! crosses it counts the new day's steps only, never a negative figure.
    function stepsBetween(startSteps as Number, endSteps as Number) as Number {
        return endSteps >= startSteps ? endSteps - startSteps : endSteps;
    }
}
