import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:glance)
module Fmt {
    // 754 -> "12:34", 4557 -> "1:15:57"
    function clock(secs as Number) as String {
        if (secs < 0) { secs = 0; }
        var h = secs / 3600;
        var m = (secs % 3600) / 60;
        var s = secs % 60;
        if (h > 0) {
            return h.toString() + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.toString() + ":" + s.format("%02d");
    }

    // 7800 -> "2h 10m", 600 -> "10m", 20 -> "now"
    function ago(secs as Number) as String {
        if (secs < 60) { return "now"; }
        var h = secs / 3600;
        var m = (secs % 3600) / 60;
        if (h > 0) { return h.toString() + "h " + m.toString() + "m"; }
        return m.toString() + "m";
    }

    // epoch -> local "14:36"
    function hm(ts as Number) as String {
        var i = Gregorian.info(new Time.Moment(ts), Time.FORMAT_SHORT);
        return (i.hour as Number).format("%02d") + ":" + (i.min as Number).format("%02d");
    }

    function sideName(s as String) as String {
        return s.equals("L") ? "Left" : "Right";
    }
}
