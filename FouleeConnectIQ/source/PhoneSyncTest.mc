import Toybox.Lang;
import Toybox.Test;

//! The message as `GarminPhoneSync` builds it on the phone. A module, not a
//! global function: Run No Evil runs every global `(:test)` function as a
//! test, with a Logger this one does not take.
(:test)
module PhoneSyncFixture {
    function message() as Dictionary<String, Object> {
        return {
            "t" => "sync",
            "v" => 1,
            "streak" => 12,
            "minutesGoal" => 30,
            "stepsGoal" => 8000,
            "mode" => "both",
            "water" => true,
            "waterGoalML" => 2000,
            "glassML" => 250
        };
    }
}

(:test)
function phoneSyncDecodesTheWholeState(logger as Logger) as Boolean {
    var state = PhoneSync.decode(PhoneSyncFixture.message());
    Test.assert(state != null);
    var decoded = state as Dictionary<String, Number or Boolean or String>;
    Test.assertEqual(decoded["streak"] as Object, 12);
    Test.assertEqual(decoded["minutesGoal"] as Object, 30);
    Test.assertEqual(decoded["stepsGoal"] as Object, 8000);
    Test.assertEqual(decoded["mode"] as Object, "both");
    Test.assertEqual(decoded["water"] as Object, true);
    Test.assertEqual(decoded["waterGoalML"] as Object, 2000);
    Test.assertEqual(decoded["glassML"] as Object, 250);

    logger.debug("sync = " + decoded.toString());
    return true;
}

(:test)
function phoneSyncRefusesWhatItDoesNotUnderstand(logger as Logger) as Boolean {
    var otherType = PhoneSyncFixture.message();
    otherType["t"] = "session";
    Test.assert(PhoneSync.decode(otherType) == null);

    var newerVersion = PhoneSyncFixture.message();
    newerVersion["v"] = 2;
    Test.assert(PhoneSync.decode(newerVersion) == null);

    Test.assert(PhoneSync.decode(null) == null);
    Test.assert(PhoneSync.decode("sync") == null);

    logger.debug("foreign messages refused");
    return true;
}

(:test)
function phoneSyncFieldsFallBackInsteadOfFailing(logger as Logger) as Boolean {
    var message = PhoneSyncFixture.message();
    message.remove("streak");
    message["stepsGoal"] = "8000";
    message["mode"] = "swimming";
    message["water"] = 1;
    var decoded = PhoneSync.decode(message) as Dictionary<String, Number or Boolean or String>;
    Test.assertEqual(decoded["streak"] as Object, 0);
    Test.assertEqual(decoded["stepsGoal"] as Object, 0);
    Test.assertEqual(decoded["mode"] as Object, "walking");
    Test.assertEqual(decoded["water"] as Object, false);

    logger.debug("lenient fields");
    return true;
}

(:test)
function phoneSyncReceiveStoresOnlyWhatItUnderstands(logger as Logger) as Boolean {
    Test.assert(PhoneSync.receive(PhoneSyncFixture.message()));
    var stored = PhoneSync.load() as Dictionary<String, Number or Boolean or String>;
    Test.assertEqual(stored["streak"] as Object, 12);

    var newer = PhoneSyncFixture.message();
    newer["v"] = 2;
    newer["streak"] = 99;
    Test.assert(!PhoneSync.receive(newer));
    stored = PhoneSync.load() as Dictionary<String, Number or Boolean or String>;
    Test.assertEqual(stored["streak"] as Object, 12);

    logger.debug("only understood messages stored");
    return true;
}
