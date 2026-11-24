import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

function near(a as Number, b as Number) as Boolean {
    return (a - b).abs() <= 2;
}

function resetAll() as Void {
    Storage.clearValues();
}

// Simulate time passing by moving the live segment's start back.
function rewind(secs as Number) as Void {
    var s = Store.session() as Dictionary;
    if ((s["run"] as Number) >= 0) { s["run"] = (s["run"] as Number) - secs; }
    s["start"] = (s["start"] as Number) - secs;
    if ((s["pausedAt"] as Number) > 0) { s["pausedAt"] = (s["pausedAt"] as Number) - secs; }
    Storage.setValue(Store.K_SESSION, s);
}

(:test)
function testFmt(logger as Logger) as Boolean {
    Test.assertEqual(Fmt.clock(4557), "1:15:57");
    Test.assertEqual(Fmt.clock(754), "12:34");
    Test.assertEqual(Fmt.clock(9), "0:09");
    Test.assertEqual(Fmt.ago(7800), "2h 10m");
    Test.assertEqual(Fmt.ago(600), "10m");
    return true;
}

(:test)
function testSingleSideStartedEarlier(logger as Logger) as Boolean {
    resetAll();
    Store.startSession("L", 600);                 // "started 10 min ago"
    var s = Store.session() as Dictionary;
    Test.assert(Store.isRunning(s));
    Test.assert(near(Store.sideSecs(s, "L"), 600));
    Test.assertEqual(Store.sideSecs(s, "R"), 0);
    var e = Store.finish() as Dictionary;
    Test.assert(near(e["l"] as Number, 600));
    Test.assertEqual(e["r"], 0);
    Test.assertEqual(e["first"], "L");
    Test.assert(near((e["end"] as Number) - (e["start"] as Number), 600));
    Test.assertEqual(Store.queue().size(), 1);
    Test.assert(Store.session() == null);
    Test.assertEqual(Store.lastEndSide(), "L");
    resetAll();
    return true;
}

(:test)
function testSwitchAndPause(logger as Logger) as Boolean {
    resetAll();
    Store.startSession("R", 0);
    rewind(300);                                  // 5 min on right
    Store.switchSide();
    rewind(240);                                  // 4 min on left
    Store.togglePause();                          // pause
    var s = Store.session() as Dictionary;
    Test.assert(!Store.isRunning(s));
    Test.assert(near(Store.sideSecs(s, "R"), 300));
    Test.assert(near(Store.sideSecs(s, "L"), 240));
    rewind(600);                                  // paused for 10 min (wall clock moves, nursing time doesn't)
    s = Store.session() as Dictionary;
    Test.assert(near(Store.sideSecs(s, "L"), 240));
    var e = Store.finish() as Dictionary;
    Test.assertEqual(e["first"], "R");
    Test.assert(near(e["r"] as Number, 300));
    Test.assert(near(e["l"] as Number, 240));
    // end = moment of pause, not when Stop was pressed
    Test.assert(near((e["end"] as Number) - (e["start"] as Number), 540));
    Test.assertEqual(Store.lastEndSide(), "L");
    resetAll();
    return true;
}

(:test)
function testResumeAfterPause(logger as Logger) as Boolean {
    resetAll();
    Store.startSession("L", 0);
    rewind(120);
    Store.togglePause();
    rewind(300);
    Store.togglePause();                          // resume
    rewind(60);
    var e = Store.finish() as Dictionary;
    Test.assert(near(e["l"] as Number, 180));
    resetAll();
    return true;
}

(:test)
function testZeroLengthDiscarded(logger as Logger) as Boolean {
    resetAll();
    Store.startSession("L", 0);
    Store.togglePause();
    Test.assert(Store.finish() == null);
    Test.assertEqual(Store.queue().size(), 0);
    return true;
}

(:test)
function testQueueAck(logger as Logger) as Boolean {
    resetAll();
    Store.startSession("L", 300);
    var a = Store.finish() as Dictionary;
    Store.startSession("R", 200);
    var b = Store.finish() as Dictionary;
    Test.assertEqual(Store.queue().size(), 2);
    Store.removeFromQueue([a["id"]]);
    Test.assertEqual(Store.queue().size(), 1);
    Test.assertEqual((Store.queue()[0] as Dictionary)["id"], b["id"]);
    var h = Store.recent();
    Test.assertEqual((h[0] as Dictionary)["ok"], false);   // b (newest first)
    Test.assertEqual((h[1] as Dictionary)["ok"], true);    // a
    Store.removeFromQueue([b["id"], "unknown"]);
    Test.assertEqual(Store.queue().size(), 0);
    resetAll();
    return true;
}

(:test)
function testStopEndedEarlier(logger as Logger) as Boolean {
    resetAll();
    Store.startSession("L", 0);
    rewind(600);                                  // 10 min on left
    Store.switchSide();
    rewind(1800);                                 // right "running" 30 min, but she stopped 25 min ago
    var e = Store.finishEarlier(25 * 60) as Dictionary;
    Test.assert(near(e["l"] as Number, 600));
    Test.assert(near(e["r"] as Number, 300));     // only 5 real minutes on right
    Test.assert(near((e["end"] as Number) - (e["start"] as Number), 900));
    Test.assert(!Store.activeDirty() == false);   // live state marked for sending
    resetAll();
    return true;
}

(:test)
function testStopEarlierThanSegment(logger as Logger) as Boolean {
    resetAll();
    Store.startSession("R", 0);
    rewind(300);
    var e = Store.finishEarlier(3600);            // more than the feed lasted
    Test.assert(e == null);                       // nothing left -> not saved
    resetAll();
    return true;
}
