//-----------------------------------------------------------------------------
// Backhaul - https://github.com/tallekene/backhaul
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
            // Discarding is not recoverable, so it gets the standard Garmin
            // confirmation rather than firing on a single button press.
            WatchUi.pushView(
                new WatchUi.Confirmation(WatchUi.loadResource(Rez.Strings.ConfirmClear) as Lang.String),
                new ClearQueueDelegate(mView),
                WatchUi.SLIDE_UP);
        }
    }

    hidden function sendTest() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);

        var blocked = mView.blocker();
        if (blocked != null) {
            mView.setTransient(blocked);
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

//! Yes/no handler for "Discard queued".
//!
//! Deliberately does not pop the menu underneath the confirmation. Garmin
//! documents neither the order in which the confirmation dismisses itself nor
//! its own example calling popView here, so a pop from this callback risks
//! taking the confirmation rather than the menu. Leaving the stack alone is
//! correct either way: the user backs out to a status screen that already
//! reflects the cleared queue.
class ClearQueueDelegate extends WatchUi.ConfirmationDelegate {

    hidden var mView as StatusView;

    function initialize(view as StatusView) {
        ConfirmationDelegate.initialize();
        mView = view;
    }

    function onResponse(response) as Lang.Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            EventQueue.clear();
            mView.setTransient(null);
        }
        return true;
    }
}
