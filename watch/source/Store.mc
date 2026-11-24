import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// All persistent state. Times are epoch seconds (UTC).
// Session: {"first","side"=>"L"|"R","start","run"(segment start or -1 when paused),"l","r","pausedAt"(-1 if running)}
(:background :glance)
module Store {
    const K_QUEUE = "q";      // events waiting for upload
    const K_SESSION = "s";    // the running/paused feed
    const K_RECENT = "h";     // last 6 saved events (with "ok" flag once uploaded)
    const K_SYNC = "sync";    // {"t"=>ts, "code"=>http code}
    const K_ACTIVE_DIRTY = "ad"; // live state changed and not yet sent
    const MAX_QUEUE = 200;
    const NUDGE_SECS = 45 * 60;  // "still feeding?" reminder

    function devId() as String {
        var ds = System.getDeviceSettings();
        if (ds has :uniqueIdentifier) {
            var u = ds.uniqueIdentifier;
            if (u != null && u.length() > 0) {
                return "w" + u.substring(0, 12);
            }
        }
        return "garmin";
    }

    // Release builds ship with no backend: everything works on the watch, nothing syncs.
    function syncEnabled() as Boolean {
        return Config.URL.length() > 0;
    }

    function activeDirty() as Boolean {
        return Storage.getValue(K_ACTIVE_DIRTY) == true;
    }

    function _dirty() as Void {
        Storage.setValue(K_ACTIVE_DIRTY, true);
    }

    function now() as Number {
        return Time.now().value();
    }

    // ---------- queue ----------
    function queue() as Array {
        var q = Storage.getValue(K_QUEUE);
        return (q instanceof Array) ? q : [];
    }

    function recent() as Array {
        var h = Storage.getValue(K_RECENT);
        return (h instanceof Array) ? h : [];
    }

    function lastSync() as Dictionary? {
        var s = Storage.getValue(K_SYNC);
        return (s instanceof Dictionary) ? s : null;
    }

    function removeFromQueue(ids as Array) as Void {
        if (ids.size() == 0) {
            return;
        }
        var q = queue();
        var out = [];
        for (var i = 0; i < q.size(); i++) {
            var e = q[i] as Dictionary;
            if (ids.indexOf(e["id"]) < 0) {
                out.add(e);
            }
        }
        Storage.setValue(K_QUEUE, out);
        var h = recent();
        for (var i = 0; i < h.size(); i++) {
            var e = h[i] as Dictionary;
            if (ids.indexOf(e["id"]) >= 0) {
                e["ok"] = true;
            }
        }
        Storage.setValue(K_RECENT, h);
    }

    // ---------- session ----------
    function session() as Dictionary? {
        var s = Storage.getValue(K_SESSION);
        return (s instanceof Dictionary) ? s : null;
    }

    function isRunning(s as Dictionary) as Boolean {
        return (s["run"] as Number) >= 0;
    }

    // Seconds spent on one side ("L"/"R"), including the live segment.
    function sideSecs(s as Dictionary, which as String) as Number {
        var acc = (which.equals("L") ? s["l"] : s["r"]) as Number;
        if (isRunning(s) && (s["side"] as String).equals(which)) {
            acc += now() - (s["run"] as Number);
        }
        return acc;
    }

    function startSession(side as String, offsetSecs as Number) as Void {
        var t = now() - offsetSecs;
        Storage.setValue(K_SESSION, {
            "first" => side, "side" => side, "start" => t, "run" => t,
            "l" => 0, "r" => 0, "pausedAt" => -1, "nudged" => false
        });
        _dirty();
    }

    // fold the live segment into the side total
    function _bank(s as Dictionary) as Void {
        if (isRunning(s)) {
            var k = (s["side"] as String).equals("L") ? "l" : "r";
            s[k] = (s[k] as Number) + (now() - (s["run"] as Number));
            s["run"] = now();
        }
    }

    function togglePause() as Void {
        var s = session();
        if (s == null) { return; }
        if (isRunning(s)) {
            _bank(s);
            s["run"] = -1;
            s["pausedAt"] = now();
        } else {
            s["run"] = now();
            s["pausedAt"] = -1;
        }
        Storage.setValue(K_SESSION, s);
        _dirty();
    }

    function switchSide() as Void {
        var s = session();
        if (s == null) { return; }
        _bank(s);
        s["side"] = (s["side"] as String).equals("L") ? "R" : "L";
        s["run"] = now();
        s["pausedAt"] = -1;
        Storage.setValue(K_SESSION, s);
        _dirty();
    }

    function clearSession() as Void {
        Storage.deleteValue(K_SESSION);
        _dirty();
    }

    // Stops the feed, queues it for upload. Returns the event, or null if it had no duration.
    function finish() as Dictionary? {
        return finishEarlier(0);
    }

    // Stop as if the feed ended `offset` seconds ago (for a forgotten stop).
    // Only the live segment is trimmed; a paused feed ends at the moment it was paused.
    function finishEarlier(offset as Number) as Dictionary? {
        var s = session();
        if (s == null) { return null; }
        var end = now() - offset;
        if (isRunning(s)) {
            var run = s["run"] as Number;
            if (end < run) { end = run; }
            var k = (s["side"] as String).equals("L") ? "l" : "r";
            s[k] = (s[k] as Number) + (end - run);
        } else if ((s["pausedAt"] as Number) > 0) {
            end = s["pausedAt"] as Number;
        }
        var l = s["l"] as Number;
        var r = s["r"] as Number;
        clearSession();
        if (l + r <= 0) {
            return null;
        }
        var start = s["start"] as Number;
        var id = start.toString() + "-" + (Math.rand() % 1000000).toString();
        var e = {"id" => id, "start" => start, "end" => end, "first" => s["first"],
                 "l" => l, "r" => r, "dev" => devId()};
        var q = queue();
        q.add(e);
        if (q.size() > MAX_QUEUE) {
            q = q.slice(q.size() - MAX_QUEUE, null);
        }
        Storage.setValue(K_QUEUE, q);
        var h = [{"id" => id, "start" => start, "first" => s["first"], "l" => l, "r" => r, "ok" => false}];
        var old = recent();
        for (var i = 0; i < old.size() && i < 5; i++) {
            h.add(old[i]);
        }
        Storage.setValue(K_RECENT, h);
        return e;
    }

    // Side the last feed ended on ("L"/"R"), or null.
    function lastEndSide() as String? {
        var h = recent();
        if (h.size() == 0) { return null; }
        var e = h[0] as Dictionary;
        var l = e["l"] as Number;
        var r = e["r"] as Number;
        if (l > 0 && r > 0) {
            return (e["first"] as String).equals("L") ? "R" : "L";
        }
        return l > 0 ? "L" : "R";
    }
}
