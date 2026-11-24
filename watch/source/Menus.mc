import Toybox.Attention;
import Toybox.Lang;
import Toybox.WatchUi;

module Ui {
    function vibe(ms as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(60, ms)]);
        }
    }

    function sync() as Void {
        var s = $.gSync;
        if (s != null) { s.kick(); }
    }

    function mainMenu() as WatchUi.Menu2 {
        var title = "Feeds";
        var lastSide = Store.lastEndSide();
        if (lastSide != null) {
            var e0 = Store.recent()[0] as Dictionary;
            title = "Last " + lastSide + " · " + Fmt.ago(Store.now() - (e0["start"] as Number));
        }
        var m = new WatchUi.Menu2({:title => title});
        var s = Store.session();
        if (s != null) {
            var secs = Store.sideSecs(s, "L") + Store.sideSecs(s, "R");
            m.addItem(new WatchUi.MenuItem("Resume timer",
                Fmt.sideName(s["side"] as String) + " " + Fmt.clock(secs), :resume, null));
        } else {
            var last = Store.lastEndSide();   // suggest the other side
            m.addItem(new WatchUi.MenuItem("Left", (last != null && last.equals("R")) ? "Next side" : null, :left, null));
            m.addItem(new WatchUi.MenuItem("Right", (last != null && last.equals("L")) ? "Next side" : null, :right, null));
            m.addItem(new WatchUi.MenuItem("Started earlier", null, :earlier, null));
        }
        m.addItem(new WatchUi.MenuItem("Recent & sync", statusLine(), :recent, null));
        return m;
    }

    function statusLine() as String {
        var h = Store.recent();
        var txt = "No feeds yet";
        if (h.size() > 0) {
            var e = h[0] as Dictionary;
            txt = "Last " + Fmt.ago(Store.now() - (e["start"] as Number)) + " ago";
        }
        var n = Store.queue().size();
        if (n > 0) { txt += " - " + n.toString() + " unsent"; }
        return txt;
    }

    function openMain(slide as WatchUi.SlideType) as Void {
        WatchUi.switchToView(mainMenu(), new MainDelegate(), slide);
    }

    // Leave the timer: back to the Home card if that's the root, else to the menu.
    function leaveTimer(slide as WatchUi.SlideType) as Void {
        if ($.gHomeRoot) {
            WatchUi.popView(slide);
        } else {
            openMain(slide);
        }
    }

    function openTimer() as Void {
        WatchUi.switchToView(new TimerView(), new TimerDelegate(), WatchUi.SLIDE_LEFT);
    }
}

class MainDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :resume) {
            Ui.openTimer();
        } else if (id == :left || id == :right) {
            if (Store.session() == null) {
                Store.startSession(id == :left ? "L" : "R", 0);
                Ui.vibe(150);
                Ui.sync();
            }
            Ui.openTimer();
        } else if (id == :earlier) {
            var m = new WatchUi.Menu2({:title => "Started"});
            var mins = [5, 10, 15, 20, 30, 45, 60];
            for (var i = 0; i < mins.size(); i++) {
                m.addItem(new WatchUi.MenuItem(mins[i].toString() + " min ago", null, mins[i], null));
            }
            WatchUi.pushView(m, new EarlierDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :recent) {
            WatchUi.pushView(new RecentView(), new RecentDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}

class EarlierDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var mins = item.getId() as Number;
        var m = new WatchUi.Menu2({:title => mins.toString() + " min ago"});
        m.addItem(new WatchUi.MenuItem("Left", null, :left, null));
        m.addItem(new WatchUi.MenuItem("Right", null, :right, null));
        WatchUi.pushView(m, new EarlierSideDelegate(mins), WatchUi.SLIDE_LEFT);
    }
}

class EarlierSideDelegate extends WatchUi.Menu2InputDelegate {
    private var _mins as Number;

    function initialize(mins as Number) {
        Menu2InputDelegate.initialize();
        _mins = mins;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        Store.startSession(item.getId() == :left ? "L" : "R", _mins * 60);
        Ui.vibe(150);
        Ui.sync();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // side menu
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // minutes menu
        Ui.openTimer();                              // replaces main menu
    }
}

// Shown over the timer: pause/resume, switch, stop, discard
class ActionDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :pause) {
            Store.togglePause();
            Ui.sync();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :switch) {
            Store.switchSide();
            Ui.vibe(150);
            Ui.sync();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :stopEarlier) {
            var m = new WatchUi.Menu2({:title => "Feed ended"});
            var mins = [5, 10, 15, 20, 30, 45, 60];
            for (var i = 0; i < mins.size(); i++) {
                m.addItem(new WatchUi.MenuItem(mins[i].toString() + " min ago", null, mins[i], null));
            }
            WatchUi.pushView(m, new StopEarlierDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :stop) {
            var e = Store.finish();
            Ui.vibe(e != null ? 400 : 100);
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            Ui.leaveTimer(WatchUi.SLIDE_DOWN);
            Ui.sync();
        } else if (id == :discard) {
            var m = new WatchUi.Menu2({:title => "Discard feed?"});
            m.addItem(new WatchUi.MenuItem("No, keep it", null, :no, null));
            m.addItem(new WatchUi.MenuItem("Yes, discard", null, :yes, null));
            WatchUi.pushView(m, new DiscardDelegate(), WatchUi.SLIDE_LEFT);
        }
    }

    static function build() as WatchUi.Menu2 {
        var s = Store.session();
        var m = new WatchUi.Menu2({:title => "Feed"});
        if (s != null) {
            var other = (s["side"] as String).equals("L") ? "Right" : "Left";
            m.addItem(new WatchUi.MenuItem("Stop & save", null, :stop, null));
            if (Store.isRunning(s)) {
                m.addItem(new WatchUi.MenuItem("Stop - ended earlier", "forgot to stop?", :stopEarlier, null));
            }
            m.addItem(new WatchUi.MenuItem(Store.isRunning(s) ? "Pause" : "Resume", null, :pause, null));
            m.addItem(new WatchUi.MenuItem("Switch to " + other, null, :switch, null));
            m.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
        }
        return m;
    }
}

class DiscardDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :yes) {
            Store.clearSession();
            Ui.sync();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // confirm menu
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // action menu
            Ui.leaveTimer(WatchUi.SLIDE_DOWN);            // back to Home card or menu
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}

// "Stop - ended earlier": saves the feed with its real end time.
class StopEarlierDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var mins = item.getId() as Number;
        var e = Store.finishEarlier(mins * 60);
        Ui.vibe(e != null ? 400 : 100);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // minutes menu
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // action menu
        Ui.leaveTimer(WatchUi.SLIDE_DOWN);
        Ui.sync();
    }
}
