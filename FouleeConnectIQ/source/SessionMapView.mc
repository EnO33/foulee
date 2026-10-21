import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

//! How often the route drawn over the map is renewed. Not in `onUpdate`: the
//! documentation warns that redrawing the map there makes it flicker.
const MAP_ROUTE_REFRESH_MS = 10000;

//! The Plan page (ADR 0009, D4), on the watches with built-in maps only: the
//! system's map centred on the wearer, with its navigation arrow
//! (`MapTrackView`), and the route walked so far over it. In preview mode, so
//! the map takes none of the gestures: START and BACK still pause, a swipe
//! still changes page.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SessionMapView extends WatchUi.MapTrackView {

    private var _recorder as SessionRecorder;
    private var _refresh as Timer.Timer?;

    function initialize(recorder as SessionRecorder) {
        MapTrackView.initialize();
        _recorder = recorder;
        setMapMode(WatchUi.MAP_MODE_PREVIEW);
    }

    function onShow() as Void {
        drawRoute();
        var refresh = new Timer.Timer();
        refresh.start(method(:drawRoute), $.MAP_ROUTE_REFRESH_MS, true);
        _refresh = refresh;
    }

    function onHide() as Void {
        var refresh = _refresh;
        if (refresh != null) {
            refresh.stop();
        }
        _refresh = null;
    }

    function drawRoute() as Void {
        clear();
        var points = RouteMath.thin(_recorder.routeSoFar(), RouteMath.MAX_POINTS * 2);
        if (points.size() < 4) {
            return;
        }
        var polyline = new WatchUi.MapPolyline();
        polyline.setColor(MetricPalette.DISTANCE);
        polyline.setWidth(3);
        for (var i = 0; i < points.size(); i += 2) {
            polyline.addLocation(new Position.Location({
                :latitude => points[i].toDouble() / RouteMath.SCALE,
                :longitude => points[i + 1].toDouble() / RouteMath.SCALE,
                :format => :degrees
            }));
        }
        setPolyline(polyline);
    }
}
