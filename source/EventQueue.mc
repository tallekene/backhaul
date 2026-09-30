//-----------------------------------------------------------------------------
// Backhaul - https://github.com/tallekene/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

//! A small persistent FIFO of undelivered events.
//!
//! This is the reason the app exists rather than firing && forgetting: the
//! activity-completed event arrives the instant you press stop, which is very
//! often the instant your phone is still in a locker on the other side of the
//! building. Without a queue that event is simply lost.
//!
//! Storage is only reachable from a background process on CIQ 3.2.0 && above,
//! && it throws rather than returning an error on older devices, so every
//! access here is guarded. On a device that cannot do it the app degrades to
//! deliver-or-drop && says so in the status view.
//!
//! Each event lives under its own Storage key, with a separate index holding
//! only id, timestamp && attempt count. Keeping the whole queue in one value
//! meant every push re-serialised every queued event, so the memory one write
//! needed grew with the backlog: on a device that gives the background process
//! a 32 KB heap that ran out at the second event, and Storage.setValue() raises
//! an out-of-memory error that cannot be caught, so it killed the process
//! rather than degrading. A write now costs one event whatever the depth, &&
//! expiry && attempt counting read the index alone, never an event body.
(:background, :glance)
class EventQueue {

    hidden static const KEY_INDEX  = "bh_qidx";
    hidden static const KEY_LAST   = "bh_last";
    hidden static const KEY_PREFIX = "bh_q";

    //! The old single-array queue. Deleted on sight rather than migrated: it
    //! only ever held what the device could write, which on the watches this
    //! change is for was one event.
    hidden static const KEY_LEGACY = "bh_queue";

    //! Well under the per-value storage ceiling at a few hundred bytes per
    //! event, && enough to cover a long weekend away from the phone.
    static const MAX_ITEMS = 25;

    //! An event nobody could deliver in two days is not worth delivering.
    static const MAX_AGE_SECONDS = 172800;

    //! Give up on an event that keeps failing, so one poisoned payload cannot
    //! block the queue behind it forever.
    static const MAX_ATTEMPTS = 10;

    //! Index entry layout: [id, ts, attempts], all plain Numbers.
    static const I_ID       = 0;
    static const I_TS       = 1;
    static const I_ATTEMPTS = 2;

    //! Refuse a write that would leave less heap than this. The failure cannot
    //! be caught after the fact, so the only safe handling is not to try.
    hidden static const MIN_FREE_BYTES = 3072;

    hidden static var mSupported = null;

    //! Whether persistent queueing works in this process on this device.
    //! Determined by trying it once, because there is no capability flag for
    //! "Storage works in the background".
    static function isSupported() as Lang.Boolean {
        if (mSupported == null) {
            try {
                Storage.getValue(KEY_INDEX);
                mSupported = true;
            } catch (ex) {
                mSupported = false;
            }
        }
        return mSupported;
    }

    //! The index, oldest first, with anything expired already dropped and its
    //! body deleted. Entries are [id, ts, attempts], small enough to hold for a
    //! whole drain run without crowding out the event being sent.
    static function index() as Lang.Array {
        if (!isSupported()) {
            return [];
        }
        return expire(loadIndex());
    }

    //! One event body by id, or null if it is no longer there.
    static function get(id) as Lang.Dictionary or Null {
        try {
            return Storage.getValue(key(id)) as Lang.Dictionary;
        } catch (ex) {
            return null;
        }
    }

    //! Append an event. Returns false if it could not be persisted, in which
    //! case the caller should attempt an immediate send instead.
    static function push(event as Lang.Dictionary) as Lang.Boolean {
        if (!isSupported()) {
            return false;
        }

        var idx = expire(loadIndex());

        // Drop from the front when full: the newest event is the one the user
        // is most likely to still care about.
        while (idx.size() >= MAX_ITEMS) {
            discard(idx[0] as Lang.Array);
            idx = tail(idx);
        }

        var ts = event["ts"];
        if (ts == null) {
            ts = Time.now().value();
        }

        // Running out of heap is the other way this queue fills up, and the
        // policy is the same as hitting MAX_ITEMS: the newest event is the one
        // worth keeping, so make room at the front and try again. Bounded
        // because every pass either returns or drops one entry.
        for (var attempt = 0; attempt <= MAX_ITEMS; attempt += 1) {
            var id = freeId(idx);
            if (write(key(id), event)) {
                idx.add([id, ts, 0]);
                if (write(KEY_INDEX, idx)) {
                    return true;
                }
                // The body is stored but nothing references it. Drop it, and
                // take the on-disk index as authoritative rather than trying to
                // undo the entry we just appended.
                discardId(id);
                idx = expire(loadIndex());
            }
            if (idx.size() == 0) {
                return false;
            }
            discard(idx[0] as Lang.Array);
            idx = tail(idx);
        }
        return false;
    }

    //! Write back what a drain run left behind, deleting the body of anything
    //! no longer in the index. Called once per run, never mid-run: a write made
    //! inside a web-request callback was not visible to the next read on
    //! device, which is why Dispatcher defers every write to here.
    static function commit(idx as Lang.Array) as Lang.Boolean {
        if (!isSupported()) {
            return false;
        }

        // Linear rather than a lookup table: at most MAX_ITEMS entries, and an
        // extra Dictionary is real memory in the process this class exists to
        // keep within budget.
        var previous = loadIndex();
        for (var i = 0; i < previous.size(); i += 1) {
            var id = (previous[i] as Lang.Array)[I_ID];
            var kept = false;
            for (var j = 0; j < idx.size(); j += 1) {
                if ((idx[j] as Lang.Array)[I_ID] == id) {
                    kept = true;
                    break;
                }
            }
            if (!kept) {
                discardId(id);
            }
        }

        return write(KEY_INDEX, idx);
    }

    static function size() as Lang.Number {
        if (!isSupported()) {
            return 0;
        }
        return loadIndex().size();
    }

    static function clear() as Void {
        try {
            var idx = loadIndex();
            for (var i = 0; i < idx.size(); i += 1) {
                discard(idx[i] as Lang.Array);
            }
            Storage.deleteValue(KEY_INDEX);
        } catch (ex) {
            // Nothing useful to do; the queue is advisory.
        }
    }

    //! Remember the outcome of the last delivery so the glance && status view
    //! have something to show. Best effort only.
    static function recordResult(eventType as Lang.String, code as Lang.Number, ok as Lang.Boolean) as Void {
        // Guarded like every other write here: Storage.setValue() raises an
        // out-of-memory error that the catch below cannot see, and this runs at
        // the end of every background run. Not routed through write(), because
        // a failed status write must not mark the whole queue unsupported.
        if (!hasHeadroom()) {
            return;
        }
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

    hidden static function key(id) as Lang.String {
        return KEY_PREFIX + id.toString();
    }

    hidden static function loadIndex() as Lang.Array {
        try {
            if (Storage.getValue(KEY_LEGACY) != null) {
                Storage.deleteValue(KEY_LEGACY);
            }
        } catch (ex) {
            // Leftovers from the old layout are not worth failing over.
        }

        try {
            var idx = Storage.getValue(KEY_INDEX);
            if (idx == null) {
                return [];
            }
            return idx as Lang.Array;
        } catch (ex) {
            mSupported = false;
            return [];
        }
    }

    hidden static function write(k as Lang.String, value) as Lang.Boolean {
        if (!hasHeadroom()) {
            return false;
        }
        try {
            Storage.setValue(k, value);
            return true;
        } catch (ex) {
            mSupported = false;
            return false;
        }
    }

    //! Storage.setValue() raises an uncatchable out-of-memory error on some
    //! devices, so the free-heap check has to happen before the call.
    hidden static function hasHeadroom() as Lang.Boolean {
        var stats = System.getSystemStats();
        if (stats == null || !(stats has :freeMemory) || stats.freeMemory == null) {
            return true;
        }
        return stats.freeMemory > MIN_FREE_BYTES;
    }

    //! The lowest id not in use, so keys stay short and bounded rather than
    //! climbing with a counter that would have to be persisted as well.
    hidden static function freeId(idx as Lang.Array) as Lang.Number {
        for (var candidate = 0; candidate < MAX_ITEMS; candidate += 1) {
            var used = false;
            for (var i = 0; i < idx.size(); i += 1) {
                if ((idx[i] as Lang.Array)[I_ID] == candidate) {
                    used = true;
                    break;
                }
            }
            if (!used) {
                return candidate;
            }
        }
        return 0;
    }

    hidden static function discard(entry as Lang.Array) as Void {
        discardId(entry[I_ID]);
    }

    hidden static function discardId(id) as Void {
        try {
            Storage.deleteValue(key(id));
        } catch (ex) {
            // Best effort; an orphaned body is wasted space, not a fault.
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

    //! Drops expired entries and their bodies. Reads only the index, which is
    //! the point of keeping the timestamp there.
    hidden static function expire(idx as Lang.Array) as Lang.Array {
        var cutoff = Time.now().value() - MAX_AGE_SECONDS;
        var out = [];
        for (var i = 0; i < idx.size(); i += 1) {
            var e = idx[i] as Lang.Array;
            var ts = e[I_TS];
            if (ts == null || ts >= cutoff) {
                out.add(e);
            } else {
                discard(e);
            }
        }
        return out;
    }
}
