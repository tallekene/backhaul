//-----------------------------------------------------------------------------
// Backhaul - https://github.com/laemmlein/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Lang;
using Toybox.WatchUi;

//! Input handling for the status screen. Both the select button && the menu
//! button open the same menu, because which one a user reaches for depends
//! entirely on which Garmin they own.
class StatusDelegate extends WatchUi.BehaviorDelegate {

    hidden var mView as StatusView;

    function initialize(view as StatusView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Lang.Boolean {
        showMenu();
        return true;
    }

    function onMenu() as Lang.Boolean {
        showMenu();
        return true;
    }

    hidden function showMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => Rez.Strings.MenuStatus });

        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.MenuSendTest) as Lang.String, null, :test, {}));

        if (EventQueue.isSupported() && EventQueue.size() > 0) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.MenuFlushQueue) as Lang.String, null, :flush, {}));
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.MenuClearQueue) as Lang.String, null, :clear, {}));
        }

        WatchUi.pushView(menu, new MainMenuDelegate(mView), WatchUi.SLIDE_UP);
    }
}
