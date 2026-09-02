//-----------------------------------------------------------------------------
// Backhaul - https://github.com/laemmlein/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Time;

//! A small persistent FIFO of undelivered events.
//!
//! This is the reason the app exists rather than firing and forgetting: the
//! activity-completed event arrives the instant you press stop, which is very
//! often the instant your phone is still in a locker on the other side of the
//! building. Without a queue that event is simply lost.
//!
//! Storage is only reachable from a background process on CIQ 3.2.0 and above,
//! and it throws rather than returning an error on older devices, so every
//! access here is guarded. On a device that cannot do it the app degrades to
//! deliver-or-drop and says so in the status view.
(:background, :glance)
class EventQueue {

    hidden static const KEY_QUEUE = "bh_queue";
    hidden static const KEY_LAST  = "bh_last";

    //! Well under the 32 KB per-value storage ceiling at a few hundred bytes
    //! per event, and enough to cover a long weekend away from the phone.
    static const MAX_ITEMS = 25;

    //! An event nobody could deliver in two days is not worth delivering.
    static const MAX_AGE_SECONDS = 172800;

    //! Give up on an event that keeps failing, so one poisoned payload cannot
    //! block the queue behind it forever.
    static const MAX_ATTEMPTS = 10;

    hidden static var mSupported = null;

    //! Whether persistent queueing works in this process on this device.
    //! Determined by trying it once, because there is no capability flag for
    //! "Storage works in the background".
    static function isSupported() as Lang.Boolean {
        if (mSupported == null) {
            try {
                Storage.getValue(KEY_QUEUE);
                mSupported = true;
            } catch (ex) {
                mSupported = false;
            }
        }
        return mSupported;
    }

    hidden static function load() as Lang.Array {
        try {
            var q = Storage.getValue(KEY_QUEUE);
            if (q == null) {
                return [];
            }
            return q as Lang.Array;
        } catch (ex) {
            mSupported = false;
            return [];
        }
    }

    hidden static function save(q as Lang.Array) as Lang.Boolean {
        try {
            Storage.setValue(KEY_QUEUE, q);
            return true;
        } catch (ex) {
            // Storage.setValue() throws an out-of-memory error that cannot be
            // caught on some devices; where it can be, dropping the queue is
            // better than wedging the background service.
            mSupported = false;
            return false;
        }
    }

    //! Append an event. Returns false if it could not be persisted, in which
    //! case the caller should attempt an immediate send instead.
    static function push(event as Lang.Dictionary) as Lang.Boolean {
        if (!isSupported()) {
            return false;
        }

        var q = expire(load());

        event["attempts"] = 0;
        q.add(event);

        // Drop from the front when full: the newest event is the one the user
        // is most likely to still care about.
        while (q.size() > MAX_ITEMS) {
            q = tail(q);
        }

        return save(q);
    }

    static function size() as Lang.Number {
        if (!isSupported()) {
            return 0;
        }
        return load().size();
    }

    //! The oldest undelivered event, or null.
    static function peek() as Lang.Dictionary or Null {
        var q = load();
        if (q.size() == 0) {
            return null;
        }
        return q[0] as Lang.Dictionary;
    }

    //! Remove the oldest event, after a successful delivery or a permanent
    //! rejection.
    static function pop() as Void {
        var q = load();
        if (q.size() == 0) {
            return;
        }
        save(tail(q));
    }

    //! Record a failed attempt against the head, dropping it once it has burned
    //! through MAX_ATTEMPTS.
    static function penaliseHead() as Void {
        var q = load();
        if (q.size() == 0) {
            return;
        }

        var head = q[0] as Lang.Dictionary;
        var attempts = head["attempts"];
        if (attempts == null) {
            attempts = 0;
        }
        attempts = attempts + 1;

        if (attempts >= MAX_ATTEMPTS) {
            save(tail(q));
            return;
        }

        head["attempts"] = attempts;
        q[0] = head;
        save(q);
    }

    static function clear() as Void {
        try {
            Storage.deleteValue(KEY_QUEUE);
        } catch (ex) {
            // Nothing useful to do; the queue is advisory.
        }
    }

    //! Remember the outcome of the last delivery so the glance and status view
    //! have something to show. Best effort only.
    static function recordResult(eventType as Lang.String, code as Lang.Number, ok as Lang.Boolean) as Void {
        try {
            Storage.setValue(KEY_LAST, {
                "ts"    => Time.now().value(),
                "event" => eventType,
                "code"  => code,
                "ok"    => ok
            });
        } catch (ex) {
            // Best effort.
        }
    }

    static function lastResult() as Lang.Dictionary or Null {
        try {
            return Storage.getValue(KEY_LAST) as Lang.Dictionary;
        } catch (ex) {
            return null;
        }
    }

    //! Everything but the first element. Written out rather than using slice()
    //! so behaviour does not depend on which SDK the array method landed in.
    hidden static function tail(q as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 1; i < q.size(); i += 1) {
            out.add(q[i]);
        }
        return out;
    }

    hidden static function expire(q as Lang.Array) as Lang.Array {
        var cutoff = Time.now().value() - MAX_AGE_SECONDS;
        var out = [];
        for (var i = 0; i < q.size(); i += 1) {
            var e = q[i] as Lang.Dictionary;
            var ts = e["ts"];
            if (ts == null or ts >= cutoff) {
                out.add(e);
            }
        }
        return out;
    }
}
