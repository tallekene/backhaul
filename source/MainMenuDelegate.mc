//-----------------------------------------------------------------------------
// Backhaul - https://github.com/laemmlein/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Lang;
using Toybox.WatchUi;

//! Actions available from the status screen.
class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var mView       as StatusView;
    hidden var mDispatcher as Dispatcher or Null;

    function initialize(view as StatusView) {
        Menu2InputDelegate.initialize();
        mView = view;
        mDispatcher = null;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :test) {
            sendTest();
        } else if (id == :flush) {
            flush();
        } else if (id == :clear) {
            EventQueue.clear();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            mView.setTransient(null);
        }
    }

    hidden function sendTest() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);

        if (!Config.isUsable()) {
            mView.setTransient(WatchUi.loadResource(Rez.Strings.StatusNoUrl) as Lang.String);
            return;
        }

        mView.setTransient(WatchUi.loadResource(Rez.Strings.Sending) as Lang.String);

        // Held on the delegate, not a local: the delegate outlives this call
        // && the request needs its callback target to still exist when the
        // response comes back.
        mDispatcher = new Dispatcher(method(:onSent));
        mDispatcher.sendNow(Payload.build(Payload.EV_TEST, null));
    }

    hidden function flush() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        mView.setTransient(WatchUi.loadResource(Rez.Strings.Sending) as Lang.String);

        mDispatcher = new Dispatcher(method(:onSent));
        mDispatcher.drain();
    }

    //! Dispatcher callback. Clearing the transient message drops the view back
    //! to reporting whatever EventQueue recorded as the last result.
    function onSent() as Void {
        mView.setTransient(null);
    }
}
