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
        :steps => 3100
    }, false);
    Test.assertEqual(message["t"] as Object, "summary");
    Test.assertEqual(message["v"] as Object, 1);
    Test.assertEqual(message["sport"] as Object, "walking");
    Test.assertEqual(message["start"] as Object, 1760961600);
    Test.assertEqual(message["end"] as Object, 1760963700);
    Test.assertEqual(message["duration"] as Object, 1800);
    Test.assertEqual(message["distanceM"] as Object, 2400);
    Test.assertEqual(message["steps"] as Object, 3100);

    logger.debug("summary = " + message.toString());
    return true;
}

(:test)
function sessionMessageNamesTheRun(logger as Logger) as Boolean {
    var message = SessionMessage.summary({
        :startedAt => 0, :endedAt => 0, :seconds => 0, :meters => 0, :steps => 0
    }, true);
    Test.assertEqual(message["sport"] as Object, "running");
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
