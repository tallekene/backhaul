//-----------------------------------------------------------------------------
// Backhaul - https://github.com/laemmlein/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

//! The one screen the app has: is it working, && what did it last do.
class StatusView extends WatchUi.View {

    hidden var mTransient as Lang.String or Null;

    function initialize() {
        View.initialize();
        mTransient = null;
    }

    //! Show a short-lived message ("Sending...", "Delivered") in place of the
    //! headline. Cleared by clearTransient().
    function setTransient(text as Lang.String or Null) as Void {
        mTransient = text;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        // Lay the three lines out as fractions of the screen so this survives
        // contact with round, semi-round && rectangular devices alike, rather
        // than shipping a layout per screen size.
        drawCentred(dc, w, h * 0.28, Graphics.FONT_MEDIUM, Graphics.COLOR_WHITE, "Backhaul");
        drawCentred(dc, w, h * 0.47, Graphics.FONT_SMALL,  headlineColour(), headline());
        drawCentred(dc, w, h * 0.62, Graphics.FONT_TINY,   Graphics.COLOR_LT_GRAY, queueLine());
        drawCentred(dc, w, h * 0.74, Graphics.FONT_TINY,   Graphics.COLOR_LT_GRAY, lastLine());
    }

    hidden function drawCentred(dc as Graphics.Dc, w as Lang.Number, y as Lang.Float,
                                font, colour, text as Lang.String) as Void {
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function headline() as Lang.String {
        if (mTransient != null) {
            return mTransient;
        }
        if (!EventRegistrar.isSupported()) {
            return WatchUi.loadResource(Rez.Strings.StatusUnsupported) as Lang.String;
        }
        if (!Config.getBool("enabled", true)) {
            return WatchUi.loadResource(Rez.Strings.StatusOff) as Lang.String;
        }
        if (Config.url().length() == 0) {
            return WatchUi.loadResource(Rez.Strings.StatusNoUrl) as Lang.String;
        }
        return WatchUi.loadResource(Rez.Strings.StatusReady) as Lang.String;
    }

    hidden function headlineColour() {
        if (mTransient != null) {
            return Graphics.COLOR_YELLOW;
        }
        if (!EventRegistrar.isSupported() || !Config.isUsable()) {
            return Graphics.COLOR_RED;
        }
        return Graphics.COLOR_GREEN;
    }

    hidden function queueLine() as Lang.String {
        if (!EventQueue.isSupported()) {
            return "";
        }
        var n = EventQueue.size();
        if (n == 0) {
            return "";
        }
        return (WatchUi.loadResource(Rez.Strings.LabelQueued) as Lang.String) + ": " + n.toString();
    }

    hidden function lastLine() as Lang.String {
        var last = EventQueue.lastResult();
        if (last == null) {
            return WatchUi.loadResource(Rez.Strings.StatusNever) as Lang.String;
        }

        var outcome;
        if (last["ok"] == true) {
            outcome = WatchUi.loadResource(Rez.Strings.SendOk) as Lang.String;
        } else if (last["code"] == 0) {
            // Code 0 is our own marker for "never left the watch", as opposed
            // to a server that answered with something unhelpful.
            outcome = WatchUi.loadResource(Rez.Strings.NoPhone) as Lang.String;
        } else {
            outcome = (WatchUi.loadResource(Rez.Strings.SendFailed) as Lang.String)
                + " " + last["code"].toString();
        }

        return outcome + " " + ago(last["ts"]);
    }

    //! Coarse relative time. Minutes then hours then days is as much precision
    //! as anyone reading a status screen needs.
    hidden function ago(ts) as Lang.String {
        if (ts == null) {
            return "";
        }

        var seconds = Time.now().value() - ts;
        if (seconds < 60) {
            return "just now";
        }

        var minutes = seconds / 60;
        if (minutes < 60) {
            return minutes.toString() + "m ago";
        }

        var hours = minutes / 60;
        if (hours < 24) {
            return hours.toString() + "h ago";
        }

        return (hours / 24).toString() + "d ago";
    }
}
