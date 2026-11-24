import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class TimerView extends WatchUi.View {
    private var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:tick), 1000, true);
        _timer = t;
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) { t.stop(); }
        _timer = null;
    }

    function tick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var C = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var s = Store.session();
        if (s == null) {
            dc.drawText(cx, h / 2, Graphics.FONT_SMALL, "No feed running", C);
            return;
        }
        var running = Store.isRunning(s);
        var l = Store.sideSecs(s, "L");
        var r = Store.sideSecs(s, "R");
        var side = (s["side"] as String).equals("L") ? "LEFT" : "RIGHT";

        dc.drawText(cx, h * 22 / 100, Graphics.FONT_MEDIUM, running ? side : "PAUSED", C);
        dc.drawText(cx, h * 47 / 100, Graphics.FONT_NUMBER_MEDIUM, Fmt.clock(l + r), C);
        dc.drawText(cx, h * 68 / 100, Graphics.FONT_TINY,
            "L " + Fmt.clock(l) + "   R " + Fmt.clock(r), C);
        dc.drawText(cx, h * 82 / 100, Graphics.FONT_XTINY,
            "since " + Fmt.hm(s["start"] as Number), C);
    }
}

class TimerDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        if (Store.session() == null) {
            Ui.leaveTimer(WatchUi.SLIDE_RIGHT);
            return true;
        }
        WatchUi.pushView(ActionDelegate.build(), new ActionDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return onSelect();
    }

    // Back leaves the timer running and returns to the menu.
    function onBack() as Boolean {
        Ui.leaveTimer(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
