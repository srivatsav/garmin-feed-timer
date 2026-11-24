import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

var gSync as SyncController?;
var gHomeRoot as Boolean = false;   // true when the Home card is the first screen

(:background)
class FeedsApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    // Foreground only.
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return $.startForeground();
    }

    (:glance)
    function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [new FeedsGlance()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new SyncService()];
    }

    // Acks from the background service (in case it couldn't write storage itself).
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Array) {
            Store.removeFromQueue(data);
        }
        $.afterBackground();
    }
}

(:typecheck(disableBackgroundCheck))
function startForeground() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
    Math.srand(System.getTimer() + Store.now());
    var s = new SyncController();
    $.gSync = s;
    s.kick();   // flush anything left over from before
    var ds = System.getDeviceSettings();
    var glance = (ds has :isGlanceModeEnabled) && ds.isGlanceModeEnabled;
    if (!glance) {
        $.gHomeRoot = true;
        return [new HomeView(), new HomeDelegate()];   // widget loop card (Venu Sq)
    }
    if (Store.session() != null) {
        return [new TimerView(), new TimerDelegate()];
    }
    return [Ui.mainMenu(), new MainDelegate()];
}

(:typecheck(disableBackgroundCheck))
function afterBackground() as Void {
    var s = $.gSync;
    if (s != null) { s.schedule(); }
    WatchUi.requestUpdate();
}

(:glance)
class FeedsGlance extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var L = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h / 4, Graphics.FONT_TINY, "FEEDS", L);

        var line;
        var s = Store.session();
        if (s != null) {
            var secs = Store.sideSecs(s, "L") + Store.sideSecs(s, "R");
            line = (Store.isRunning(s) ? "" : "Paused ") + Fmt.sideName(s["side"] as String)
                + " " + Fmt.clock(secs);
        } else {
            var hist = Store.recent();
            if (hist.size() == 0) {
                line = "Tap to log a feed";
            } else {
                var e = hist[0] as Dictionary;
                var side = Store.lastEndSide();
                line = "Last: " + (side != null ? Fmt.sideName(side) : "?") + " · " + Fmt.ago(Store.now() - (e["start"] as Number)) + " ago";
            }
        }
        var n = Store.queue().size();
        if (n > 0) { line += "  (" + n.toString() + " unsent)"; }
        dc.drawText(0, h * 3 / 4, Graphics.FONT_XTINY, line, L);
    }
}
