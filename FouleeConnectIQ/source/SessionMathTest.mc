import Toybox.Lang;
import Toybox.Test;

(:test)
function sessionClockPromotesPastTheHour(logger as Logger) as Boolean {
    Test.assertEqual(SessionMath.clock(0), "00:00");
    Test.assertEqual(SessionMath.clock(462), "07:42");
    Test.assertEqual(SessionMath.clock(3725), "1:02:05");
    return true;
}

(:test)
function sessionPaceDividesTheStretch(logger as Logger) as Boolean {
    Test.assertEqual(SessionMath.pace(370, 1000), "6'10\"/km");
    Test.assertEqual(SessionMath.pace(925, 2500), "6'10\"/km");
    return true;
}

(:test)
function sessionPaceIsSilentWhenItWouldLie(logger as Logger) as Boolean {
    Test.assert(SessionMath.pace(30, 49) == null);
    Test.assert(SessionMath.pace(0, 1000) == null);
    Test.assert(SessionMath.pace(99 * 60, 1000) == null);
    return true;
}

(:test)
function sessionLivePaceRoundsToTheSport(logger as Logger) as Boolean {
    // 2.75 m/s is 363.6 s/km: 365 running (step 5), 360 walking (step 10).
    Test.assertEqual(SessionMath.livePace(2.75f, true), "6'05\"/km");
    Test.assertEqual(SessionMath.livePace(2.75f, false), "6'00\"/km");
    Test.assert(SessionMath.livePace(null, true) == null);
    Test.assert(SessionMath.livePace(0.0f, false) == null);
    Test.assert(SessionMath.livePace(0.1f, false) == null);
    return true;
}

(:test)
function sessionKilometerAlertFiresOnceAtTheBoundary(logger as Logger) as Boolean {
    Test.assertEqual(SessionMath.kilometerCrossed(990, 999), 0);
    Test.assertEqual(SessionMath.kilometerCrossed(999, 1003), 1);
    Test.assertEqual(SessionMath.kilometerCrossed(1003, 1010), 0);
    Test.assertEqual(SessionMath.kilometerCrossed(1950, 3020), 3);
    return true;
}
