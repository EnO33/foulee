import Toybox.Lang;
import Toybox.Test;

(:test)
function complicationFeedPublishesOnlyAKnownStreak(logger as Logger) as Boolean {
    Test.assert(ComplicationFeed.streakOf(null) == null);
    Test.assertEqual(ComplicationFeed.streakOf(PhoneSync.decode(PhoneSyncFixture.message())), 12);
    return true;
}
