import Toybox.Lang;
import Toybox.Test;

(:test)
function homeProgressShowsTheGoal(logger as Logger) as Boolean {
    Test.assertEqual(HomeFormat.progress(8421, 10000, " "), "8 421 / 10 000");
    Test.assertEqual(HomeFormat.progress(47, 30, ","), "47 / 30");
    return true;
}

(:test)
function homeProgressWithoutGoalIsTheBareFigure(logger as Logger) as Boolean {
    // Zero is what PhoneSync decodes before the phone has sent a goal.
    Test.assertEqual(HomeFormat.progress(8421, 0, " "), "8 421");
    return true;
}

(:test)
function homeLineWidthFollowsTheDial(logger as Logger) as Boolean {
    Test.assertEqual(HomeFormat.lineWidth(416, 416, 208, true), 416);
    Test.assertEqual(HomeFormat.lineWidth(200, 200, 20, true), 120);
    Test.assertEqual(HomeFormat.lineWidth(200, 200, 0, true), 0);
    return true;
}

(:test)
function homeLineWidthOnASquareScreenIsTheWidth(logger as Logger) as Boolean {
    Test.assertEqual(HomeFormat.lineWidth(320, 360, 10, false), 320);
    return true;
}
