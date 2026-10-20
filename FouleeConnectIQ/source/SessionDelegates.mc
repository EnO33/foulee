import Toybox.Lang;
import Toybox.WatchUi;

//! The home's main action: START on button watches, a tap on touch screens
//! (ADR 0009, D4). In « Les deux » mode the sport is asked first (D3).
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class HomeDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        var sync = PhoneSync.load();
        var mode = sync != null ? sync["mode"] as String : PhoneSync.MODE_WALKING;
        if ("both".equals(mode)) {
            var menu = new WatchUi.Menu2({:title => WatchUi.loadResource($.Rez.Strings.ChooseSport) as String});
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource($.Rez.Strings.SportWalk) as String, null, :walk, null));
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource($.Rez.Strings.SportRun) as String, null, :run, null));
            WatchUi.pushView(menu, new SportMenuDelegate(), WatchUi.SLIDE_UP);
        } else {
            SessionFlow.start("running".equals(mode));
        }
        return true;
    }
}

//! Marche or Course, then straight into the session.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SportMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        SessionFlow.start(item.getId() == :run);
    }
}

//! During the session START (or a tap) pauses, and so does BACK: a session is
//! never left by a stray press.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SessionDelegate extends WatchUi.BehaviorDelegate {

    private var _recorder as SessionRecorder;

    function initialize(recorder as SessionRecorder) {
        BehaviorDelegate.initialize();
        _recorder = recorder;
    }

    function onSelect() as Boolean {
        pause();
        return true;
    }

    function onBack() as Boolean {
        pause();
        return true;
    }

    private function pause() as Void {
        _recorder.pause();
        var menu = new WatchUi.Menu2({:title => WatchUi.loadResource($.Rez.Strings.Paused) as String});
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource($.Rez.Strings.Resume) as String, null, :resume, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource($.Rez.Strings.Save) as String, null, :save, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource($.Rez.Strings.Discard) as String, null, :discard, null));
        WatchUi.pushView(menu, new PauseMenuDelegate(_recorder), WatchUi.SLIDE_UP);
    }
}

//! Reprendre, Enregistrer, Supprimer — the last one confirmed first.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _recorder as SessionRecorder;

    function initialize(recorder as SessionRecorder) {
        Menu2InputDelegate.initialize();
        _recorder = recorder;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :resume) {
            _recorder.resume();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :save) {
            _recorder.save();
            SessionFlow.end();
        } else if (id == :discard) {
            WatchUi.pushView(
                new WatchUi.Confirmation(WatchUi.loadResource($.Rez.Strings.DiscardConfirm) as String),
                new DiscardDelegate(_recorder),
                WatchUi.SLIDE_IMMEDIATE
            );
        }
    }

    //! BACK on the pause menu resumes, like the Apple Watch's pause.
    function onBack() as Void {
        _recorder.resume();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class DiscardDelegate extends WatchUi.ConfirmationDelegate {

    private var _recorder as SessionRecorder;

    function initialize(recorder as SessionRecorder) {
        ConfirmationDelegate.initialize();
        _recorder = recorder;
    }

    //! The confirmation is already off the stack here; the pause menu and the
    //! session page are popped by `SessionFlow.end`.
    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _recorder.discard();
            SessionFlow.end();
        }
        return true;
    }
}
