import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class RecentView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var C = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var f = Graphics.FONT_XTINY;
        var lh = dc.getFontHeight(f);
        var y = h * 16 / 100;
        dc.drawText(cx, y, Graphics.FONT_TINY, "Recent", C);
        y += lh + 4;

        var list = Store.recent();
        if (list.size() == 0) {
            dc.drawText(cx, h / 2, f, "No feeds yet", C);
        }
        for (var i = 0; i < list.size() && i < 5; i++) {
            var e = list[i] as Dictionary;
            var l = e["l"] as Number;
            var r = e["r"] as Number;
            var what = (l > 0 && r > 0) ? "L+R" : (l > 0 ? "L" : "R");
            var line = Fmt.hm(e["start"] as Number) + "  " + what + " " + Fmt.clock(l + r)
                + "  " + ((e["ok"] == true) ? "sent" : "queued");
            dc.drawText(cx, y, f, line, C);
            y += lh;
        }

        var n = Store.queue().size();
        var status = n == 0 ? "All sent" : (n.toString() + " unsent");
        if (!Store.syncEnabled()) {
            status = "Sync off (no backend)";
        }
        var ls = Store.lastSync();
        if (ls != null) {
            var code = ls["code"] as Number;
            status += code == 200 ? "" : ("  (err " + code.toString() + ")");
        }
        if (!System.getDeviceSettings().phoneConnected) {
            status += "  · no phone";
        }
        var busy = $.gSync != null && ($.gSync as SyncController).busy;
        dc.drawText(cx, h * 80 / 100, f, busy ? "Sending..." : status, C);
        dc.drawText(cx, h * 89 / 100, f, "START: sync now", C);
    }
}

class RecentDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        Ui.sync();
        WatchUi.requestUpdate();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return onSelect();
    }
}
