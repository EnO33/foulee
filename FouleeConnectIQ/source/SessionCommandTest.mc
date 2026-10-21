import Toybox.Lang;
import Toybox.Test;

(:test)
function sessionCommandRecognisesOnlyTheStop(logger as Logger) as Boolean {
    Test.assert(SessionCommand.isStop({"t" => "command", "v" => 1, "action" => "stop"}));
    Test.assert(!SessionCommand.isStop({"t" => "command", "v" => 2, "action" => "stop"}));
    Test.assert(!SessionCommand.isStop({"t" => "command", "v" => 1, "action" => "pause"}));
    Test.assert(!SessionCommand.isStop({"t" => "sync", "v" => 1}));
    Test.assert(!SessionCommand.isStop("stop"));
    Test.assert(!SessionCommand.isStop(null));
    return true;
}
