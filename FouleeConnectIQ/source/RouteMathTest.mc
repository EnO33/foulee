import Toybox.Lang;
import Toybox.Test;

(:test)
function routeMathMeasuresAWalkingStep(logger as Logger) as Boolean {
    // 0.001° of latitude is 111 m anywhere.
    var meters = RouteMath.distance(4884000, 235000, 4884100, 235000);
    Test.assert(meters > 110.0 && meters < 112.5);
    Test.assertEqual(RouteMath.toFixed(48.84123d), 4884123);
    return true;
}

(:test)
function routeMathSkipsFixesTooClose(logger as Logger) as Boolean {
    var points = RouteMath.extend([] as Array<Number>, 4884000, 235000);
    points = RouteMath.extend(points, 4884001, 235000);
    Test.assertEqual(points.size(), 2);
    points = RouteMath.extend(points, 4884100, 235000);
    Test.assertEqual(points.size(), 4);
    return true;
}

(:test)
function routeMathThinsEvenlyKeepingBothEnds(logger as Logger) as Boolean {
    var points = [] as Array<Number>;
    for (var i = 0; i < 100; i += 1) {
        points.add(i);
        points.add(-i);
    }
    var thinned = RouteMath.thin(points, 10);
    Test.assertEqual(thinned.size(), 20);
    Test.assertEqual(thinned[0], 0);
    Test.assertEqual(thinned[18], 99);
    Test.assertEqual(thinned[19], -99);
    Test.assertEqual(RouteMath.thin(thinned, 10).size(), 20);
    return true;
}
