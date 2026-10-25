import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

(:test)
function sessionMessageCarriesTheWholeSummary(logger as Logger) as Boolean {
    var message = SessionMessage.summary({
        :startedAt => 1760961600,
        :endedAt => 1760963700,
        :seconds => 1800,
        :meters => 2400,
        :ascent => 120,
        :descent => 115,
        :steps => 3100
    }, false, [4884000, 235000, 4884100, 235000] as Array<Number>);
    Test.assertEqual(message["t"] as Object, "summary");
    Test.assertEqual(message["v"] as Object, 1);
    Test.assertEqual(message["sport"] as Object, "walking");
    Test.assertEqual(message["start"] as Object, 1760961600);
    Test.assertEqual(message["end"] as Object, 1760963700);
    Test.assertEqual(message["duration"] as Object, 1800);
    Test.assertEqual(message["distanceM"] as Object, 2400);
    Test.assertEqual(message["ascentM"] as Object, 120);
    Test.assertEqual(message["descentM"] as Object, 115);
    Test.assertEqual(message["steps"] as Object, 3100);
    Test.assertEqual((message["route"] as Array<Number>).size(), 4);

    logger.debug("summary = " + message.toString());
    return true;
}

(:test)
function sessionMessageNamesTheRun(logger as Logger) as Boolean {
    var message = SessionMessage.summary({
        :startedAt => 0, :endedAt => 0, :seconds => 0, :meters => 0, :ascent => 0, :descent => 0, :steps => 0
    }, true, [] as Array<Number>);
    Test.assertEqual(message["sport"] as Object, "running");
    return true;
}

(:test)
function sessionStateCarriesTheWholeSession(logger as Logger) as Boolean {
    var message = SessionMessage.state({
        :startedAt => 1760961600,
        :endedAt => 1760962200,
        :seconds => 540,
        :meters => 900,
        :steps => 1200,
        :heartRate => 112
    }, true, true, false);
    Test.assertEqual(message["t"] as Object, "session");
    Test.assertEqual(message["v"] as Object, 1);
    Test.assertEqual(message["sport"] as Object, "running");
    Test.assertEqual(message["sent"] as Object, 1760962200);
    Test.assertEqual(message["elapsed"] as Object, 540);
    Test.assertEqual(message["distanceM"] as Object, 900);
    Test.assertEqual(message["steps"] as Object, 1200);
    Test.assertEqual(message["hr"] as Object, 112);
    Test.assertEqual(message["paused"] as Object, 1);
    Test.assertEqual(message["ended"] as Object, 0);

    logger.debug("session = " + message.toString());
    return true;
}

(:test)
function outboxKeepsTheNewestWithinCapacity(logger as Logger) as Boolean {
    Storage.deleteValue(Outbox.KEY_MESSAGES);
    for (var i = 0; i < Outbox.CAPACITY + 2; i += 1) {
        Outbox.enqueue({"start" => i});
    }
    Test.assertEqual(Outbox.load().size(), Outbox.CAPACITY);
    Test.assertEqual((Outbox.peek() as Dictionary)["start"] as Object, 2);

    Outbox.dropHead();
    Test.assertEqual((Outbox.peek() as Dictionary)["start"] as Object, 3);

    Storage.deleteValue(Outbox.KEY_MESSAGES);
    Test.assert(Outbox.peek() == null);
    return true;
}

(:test)
function waterMessageCarriesTheGlass(logger as Logger) as Boolean {
    var message = WaterMessage.glass(1760961600, 250, 42);
    Test.assertEqual(message["t"] as Object, "water");
    Test.assertEqual(message["v"] as Object, 1);
    Test.assertEqual(message["id"] as Object, "1760961600-42");
    Test.assertEqual(message["at"] as Object, 1760961600);
    Test.assertEqual(message["ml"] as Object, 250);
    return true;
}
