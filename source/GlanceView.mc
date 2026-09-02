//-----------------------------------------------------------------------------
// Backhaul - https://github.com/laemmlein/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Graphics;
using Toybox.Lang;
using Toybox.WatchUi;

//! The glance carousel entry: name on top, one line of state underneath.
//!
//! Glances get a much smaller memory budget than the app && are drawn while
//! the user is scrolling past, so this reads state && nothing else - no
//! network, no registration.
(:glance)
class BackhaulGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.28, Graphics.FONT_TINY,
            WatchUi.loadResource(Rez.Strings.AppName) as Lang.String,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(stateColour(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.72, Graphics.FONT_TINY, stateText(),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function stateText() as Lang.String {
        if (!Config.getBool("enabled", true)) {
            return WatchUi.loadResource(Rez.Strings.StatusOff) as Lang.String;
        }
        if (Config.url().length() == 0) {
            return WatchUi.loadResource(Rez.Strings.StatusNoUrl) as Lang.String;
        }

        var queued = EventQueue.size();
        if (queued > 0) {
            return (WatchUi.loadResource(Rez.Strings.LabelQueued) as Lang.String) + ": " + queued.toString();
        }

        var last = EventQueue.lastResult();
        if (last == null) {
            return WatchUi.loadResource(Rez.Strings.StatusNever) as Lang.String;
        }
        return (last["ok"] == true)
            ? WatchUi.loadResource(Rez.Strings.SendOk) as Lang.String
            : WatchUi.loadResource(Rez.Strings.SendFailed) as Lang.String;
    }

    hidden function stateColour() {
        if (!Config.isUsable()) {
            return Graphics.COLOR_RED;
        }
        var last = EventQueue.lastResult();
        if (last != null && last["ok"] != true) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_GREEN;
    }
}
