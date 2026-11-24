import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Quick-start card: first screen on watches without glances (Venu Sq widget loop).
//   idle:    "Last: RIGHT · 2h 10m ago" + two big buttons [L] [R] (suggested side filled)
//            tap L/R = start that side, top button (START) = start the suggested side,
//            tap the top text = full menu (started earlier, recent & sync)
//   feeding: live timer; tap or START = Stop / Pause / Switch menu
class HomeView extends WatchUi.View {
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

    // Button band in screen pixels (used by the delegate for hit-testing).
    static function bandTop(h as Number) as Number { return h * 40 / 100; }
    static function bandBottom(h as Number) as Number { return h * 80 / 100; }

    static function suggested() as String {
        var last = Store.lastEndSide();
        if (last == null) { return "L"; }
        return last.equals("L") ? "R" : "L";
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
        if (s != null) {
            var secs = Store.sideSecs(s, "L") + Store.sideSecs(s, "R");
            dc.drawText(cx, h * 20 / 100, Graphics.FONT_XTINY, Store.isRunning(s) ? "FEEDING" : "PAUSED", C);
            dc.drawText(cx, h * 37 / 100, Graphics.FONT_LARGE, Fmt.sideName(s["side"] as String).toUpper(), C);
            dc.drawText(cx, h * 58 / 100, Graphics.FONT_NUMBER_MILD, Fmt.clock(secs), C);
            dc.drawText(cx, h * 76 / 100, Graphics.FONT_XTINY, "since " + Fmt.hm(s["start"] as Number), C);
            dc.drawText(cx, h * 88 / 100, Graphics.FONT_XTINY, "tap: stop / switch", C);
            return;
        }

        // header: last feed
        var hist = Store.recent();
        if (hist.size() > 0) {
            var e = hist[0] as Dictionary;
            var last = Store.lastEndSide() as String;
            dc.drawText(cx, h * 16 / 100, Graphics.FONT_SMALL, "Last: " + Fmt.sideName(last).toUpper(), C);
            dc.drawText(cx, h * 29 / 100, Graphics.FONT_XTINY,
                Fmt.ago(Store.now() - (e["start"] as Number)) + " ago · " + Fmt.hm(e["start"] as Number), C);
        } else {
            dc.drawText(cx, h * 20 / 100, Graphics.FONT_SMALL, "Feeds", C);
        }

        // two big buttons
        var next = suggested();
        var top = bandTop(h);
        var bh = bandBottom(h) - top;
        var gap = w * 4 / 100;
        var bw = (w * 84 / 100 - gap) / 2;
        var x0 = w * 8 / 100;
        var sides = ["L", "R"];
        for (var i = 0; i < 2; i++) {
            var x = x0 + i * (bw + gap);
            var filled = (sides[i] as String).equals(next);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (filled) {
                dc.fillRoundedRectangle(x, top, bw, bh, 12);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setPenWidth(3);
                dc.drawRoundedRectangle(x, top, bw, bh, 12);
            }
            dc.drawText(x + bw / 2, top + bh * 42 / 100, Graphics.FONT_LARGE, sides[i] as String, C);
            dc.drawText(x + bw / 2, top + bh * 78 / 100, Graphics.FONT_XTINY, filled ? "next" : "", C);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var n = Store.queue().size();
        dc.drawText(cx, h * 89 / 100, Graphics.FONT_XTINY,
            n > 0 ? (n.toString() + " unsent") : "tap a side to start", C);
    }
}

// InputDelegate (not BehaviorDelegate): on the Venu Sq a BehaviorDelegate turns every tap into
// onSelect, which loses the tap position. Here taps and buttons arrive separately.
class HomeDelegate extends WatchUi.InputDelegate {
    function initialize() {
        InputDelegate.initialize();
    }

    function start(side as String) as Void {
        if (Store.session() == null) {
            Store.startSession(side, 0);
            Ui.vibe(200);
            Ui.sync();
        }
        WatchUi.pushView(new TimerView(), new TimerDelegate(), WatchUi.SLIDE_LEFT);
    }

    // Buttons: START/top = start suggested side (or Stop/Switch menu while feeding); MENU = full menu.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var k = evt.getKey();
        if (k == WatchUi.KEY_ENTER || k == WatchUi.KEY_START) {
            if (Store.session() != null) {
                openActions();
            } else {
                start(HomeView.suggested());
            }
            return true;
        }
        if (k == WatchUi.KEY_MENU) {
            openMenu();
            return true;
        }
        return false;   // BACK etc.: let the system handle it
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        if (Store.session() != null) {
            openActions();
            return true;
        }
        var xy = evt.getCoordinates();
        var ds = System.getDeviceSettings();
        var w = ds.screenWidth;
        var h = ds.screenHeight;
        if (xy[1] >= HomeView.bandTop(h) - 6 && xy[1] <= HomeView.bandBottom(h) + 6) {
            start(xy[0] < w / 2 ? "L" : "R");
        } else {
            openMenu();
        }
        return true;
    }

    function openMenu() as Void {
        WatchUi.pushView(Ui.mainMenu(), new MainDelegate(), WatchUi.SLIDE_LEFT);
    }

    // Timer with its Stop / Pause / Switch menu on top: two taps to stop a feed.
    function openActions() as Void {
        WatchUi.pushView(new TimerView(), new TimerDelegate(), WatchUi.SLIDE_IMMEDIATE);
        WatchUi.pushView(ActionDelegate.build(), new ActionDelegate(), WatchUi.SLIDE_UP);
    }
}
