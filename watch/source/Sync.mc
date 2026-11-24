import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Uploads up to 10 queued events. Used by both the app and the background service.
(:background)
class Uploader {
    private var _done as Method?;

    function initialize() {
    }

    // Returns false if there was nothing to send (or this build has no backend).
    function upload(done as Method) as Boolean {
        if (!Store.syncEnabled()) {
            return false;
        }
        var q = Store.queue();
        if (q.size() == 0) {
            return false;
        }
        var batch = q.size() > 5 ? q.slice(0, 5) : q;   // small batches: 32 KB background limit on older watches
        _done = done;
        Communications.makeWebRequest(
            Config.URL + "/events",
            {"events" => batch},
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + Config.TOKEN
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onResponse)
        );
        return true;
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        var acked = [];
        if (code == 200 && data instanceof Dictionary) {
            var ok = data["ok"];
            if (ok instanceof Array) {
                acked = ok;
            }
        }
        try {
            if (acked.size() > 0) {
                Store.removeFromQueue(acked);
            }
            Storage.setValue(Store.K_SYNC, {"t" => Store.now(), "code" => code});
        } catch (ex) {
            // background storage writes unsupported: the app applies acks via onBackgroundData
        }
        var cb = _done;
        if (cb != null) {
            cb.invoke(code == 200, acked);
        }
    }
}

// Sends the running feed's live state (or "none") so the phone page can show "Feeding now".
(:background)
class ActiveUploader {
    private var _done as Method?;

    function initialize() {
    }

    function post(done as Method) as Boolean {
        if (!Store.syncEnabled()) {
            return false;
        }
        var s = Store.session();
        if (s == null && !Store.activeDirty()) {
            return false;
        }
        var body = {"dev" => Store.devId()};
        if (s != null) {
            body["s"] = {"start" => s["start"], "first" => s["first"], "side" => s["side"],
                         "l" => s["l"], "r" => s["r"], "run" => s["run"], "pausedAt" => s["pausedAt"]};
        }
        _done = done;
        Communications.makeWebRequest(
            Config.URL + "/active",
            body,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + Config.TOKEN
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onResponse)
        );
        return true;
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200) {
            try { Storage.setValue(Store.K_ACTIVE_DIRTY, false); } catch (ex) { }
        }
        var cb = _done;
        if (cb != null) {
            cb.invoke(code == 200);
        }
    }
}

// Runs every 5 minutes while feeds are unsent or a feed is running, even when the app is closed.
(:background)
class SyncService extends System.ServiceDelegate {
    private var _up as Uploader?;
    private var _au as ActiveUploader?;
    private var _acked as Array = [];

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        nudgeIfLong();
        var up = new Uploader();
        _up = up;
        if (!up.upload(method(:onEventsDone))) {
            onEventsDone(true, []);
        }
    }

    // "Still feeding?" once per feed, after NUDGE_SECS of nursing time.
    function nudgeIfLong() as Void {
        var s = Store.session();
        if (s == null || !Store.isRunning(s) || s["nudged"] == true) {
            return;
        }
        var secs = Store.sideSecs(s, "L") + Store.sideSecs(s, "R");
        if (secs < Store.NUDGE_SECS) {
            return;
        }
        try {
            s["nudged"] = true;
            Storage.setValue(Store.K_SESSION, s);
        } catch (ex) { }
        if (Background has :requestApplicationWake) {
            Background.requestApplicationWake("Feed running " + (secs / 60).toString() + " min. Still feeding?");
        }
    }

    function onEventsDone(ok as Boolean, acked as Array) as Void {
        _acked = acked;
        var a = new ActiveUploader();
        _au = a;
        if (!a.post(method(:onActiveDone))) {
            finishRun();
        }
    }

    function onActiveDone(ok as Boolean) as Void {
        finishRun();
    }

    function finishRun() as Void {
        if (Store.queue().size() == 0 && Store.session() == null && !Store.activeDirty()) {
            try { Background.deleteTemporalEvent(); } catch (ex) { }
        }
        Background.exit(_acked);
    }
}

// Foreground sync: send now, and keep the 5-minute background retry registered while anything is unsent.
class SyncController {
    private var _up as Uploader?;
    private var _au as ActiveUploader?;
    var busy as Boolean = false;

    function initialize() {
    }

    function kick() as Void {
        if (!busy) {
            var up = new Uploader();
            _up = up;
            busy = up.upload(method(:onDone));
            if (!busy) {
                postActive();
            }
        }
        schedule();
    }

    function postActive() as Void {
        var a = new ActiveUploader();
        _au = a;
        a.post(method(:onActiveDone));
    }

    function onActiveDone(ok as Boolean) as Void {
        schedule();
    }

    function onDone(ok as Boolean, acked as Array) as Void {
        busy = false;
        if (ok && acked.size() > 0 && Store.queue().size() > 0) {
            kick();   // more waiting: send the next batch
            return;
        }
        postActive();
        schedule();
        WatchUi.requestUpdate();
    }

    function schedule() as Void {
        var pending = Store.syncEnabled() &&
            (Store.queue().size() > 0 || Store.session() != null || Store.activeDirty());
        var registered = Background.getTemporalEventRegisteredTime() != null;
        if (pending && !registered) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        } else if (!pending && registered) {
            Background.deleteTemporalEvent();
        }
    }
}
