import Toybox.Lang;
import Toybox.Math;

//! The session's route as it travels to the phone (ADR 0009, D7): flat
//! `[lat, lon, lat, lon, …]` in fixed point, degrees × 100 000 (about a
//! metre), so the summary carries plain Numbers. Pure, like `SessionMath`.
//!
//! Kept small on purpose: the route rides in the outbox, which the background
//! service loads whole, and its memory pool is much smaller than the app's.
module RouteMath {

    const SCALE = 100000;

    //! A fix closer than this to the last point kept adds nothing a map shows.
    const MIN_STEP_METERS = 25;

    //! The points the summary carries at most: about a kilobyte.
    const MAX_POINTS = 64;

    //! The points kept while recording; past it they are halved, evenly.
    const BUFFER_POINTS = 512;

    //! Metres per fixed-point unit of latitude (1e-5 degree).
    const METERS_PER_UNIT = 1.1132;

    function toFixed(degrees as Double) as Number {
        return Math.round(degrees * SCALE).toNumber();
    }

    //! Metres between two fixed points, equirectangular: exact enough at the
    //! scale of a walk.
    function distance(lat1 as Number, lon1 as Number, lat2 as Number, lon2 as Number) as Float {
        var meanLatitude = Math.toRadians((lat1 + lat2) / 2.0 / SCALE);
        var dx = (lon2 - lon1) * Math.cos(meanLatitude);
        var dy = lat2 - lat1;
        return (Math.sqrt(dx * dx + dy * dy) * METERS_PER_UNIT).toFloat();
    }

    //! `points` with the fix added when it is far enough from the last one,
    //! halved once the buffer is full so a long session stays within memory.
    function extend(points as Array<Number>, lat as Number, lon as Number) as Array<Number> {
        var size = points.size();
        if (size >= 2 && distance(points[size - 2], points[size - 1], lat, lon) < MIN_STEP_METERS) {
            return points;
        }
        points.add(lat);
        points.add(lon);
        if (points.size() / 2 > BUFFER_POINTS) {
            return thin(points, BUFFER_POINTS / 2);
        }
        return points;
    }

    //! At most `max` points of `points`, evenly spread, the first and the last
    //! kept: the start and the end are what the map is read by.
    function thin(points as Array<Number>, max as Number) as Array<Number> {
        var count = points.size() / 2;
        if (count <= max) {
            return points;
        }
        var thinned = [] as Array<Number>;
        for (var i = 0; i < max; i += 1) {
            var index = i * (count - 1) / (max - 1);
            thinned.add(points[index * 2]);
            thinned.add(points[index * 2 + 1]);
        }
        return thinned;
    }
}
