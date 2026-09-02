//-----------------------------------------------------------------------------
// Backhaul - https://github.com/laemmlein/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.System;
using Toybox.Time;

//! Delivers events, one request at a time.
//!
//! A background process gets a short window to do its work && is killed when
//! it calls Background.exit(), so requests are chained strictly sequentially:
//! the next one is only started from the previous one's callback. Firing them
//! in parallel would overrun the BLE queue (error -101) && lose events.
(:background)
class Dispatcher {

    //! How many events one background wake-up may deliver. The window is short
    //! && each request costs a Bluetooth round trip; the rest keep until the
    //! next temporal event.
    static const MAX_PER_RUN = 5;

    hidden var mOnDone    as Lang.Method or Null;
    hidden var mBudget    as Lang.Number;
    hidden var mDirect    as Lang.Dictionary or Null;
    hidden var mDelivered as Lang.Number;
    hidden var mLastCode  as Lang.Number;

    //! Snapshot of the queue for this run, plus how far through it we are.
    //! Held in memory rather than re-read between deliveries - see
    //! EventQueue.snapshot() for why.
    hidden var mPending as Lang.Array or Null;
    hidden var mIndex   as Lang.Number;

    //! @param onDone Called once when this run is finished, with no arguments.
    //!               In the background that is Background.exit(); in the
    //!               foreground it refreshes the view.
    function initialize(onDone as Lang.Method or Null) {
        mOnDone    = onDone;
        mBudget    = MAX_PER_RUN;
        mDirect    = null;
        mDelivered = 0;
        mLastCode  = 0;
        mPending   = null;
        mIndex     = 0;
    }

    //! Hand a freshly captured event to the delivery machinery.
    function dispatch(event as Lang.Dictionary) as Void {
        var queued = false;
        if (Config.queueEnabled()) {
            queued = EventQueue.push(event);
        }

        if (!isOnline()) {
            // Nothing to attempt. If the queue took it we will get another go
            // at the next temporal event; if it did not, the event is lost and
            // there is genuinely nothing else we can do about it.
            EventQueue.recordResult(eventType(event), 0, false);
            finish();
            return;
        }

        if (queued) {
            drain();
        } else {
            mDirect = event;
            send(event);
        }
    }

    //! Send one event immediately, bypassing the queue.
    //!
    //! Used by the "send test event" action: a test that fails should tell the
    //! user so, not quietly pile up in the queue to be redelivered later.
    function sendNow(event as Lang.Dictionary) as Void {
        if (!isOnline()) {
            EventQueue.recordResult(eventType(event), 0, false);
            finish();
            return;
        }
        mDirect = event;
        send(event);
    }

    //! Work through the backlog. Safe to call with an empty queue.
    function drain() as Void {
        if (mPending == null) {
            mPending = EventQueue.snapshot();
            mIndex   = 0;
        }
        sendNext();
    }

    //! Deliver the item under the cursor, or stop if there is nothing left to
    //! do, no connection, or no budget.
    hidden function sendNext() as Void {
        if (mPending == null || mIndex >= mPending.size()) {
            finish();
            return;
        }
        if (!isOnline() || mBudget <= 0) {
            finish();
            return;
        }
        mBudget -= 1;
        send(mPending[mIndex] as Lang.Dictionary);
    }

    hidden function send(event as Lang.Dictionary) as Void {
        Communications.makeWebRequest(
            Config.url(),
            outbound(event),
            {
                :method       => Communications.HTTP_REQUEST_METHOD_POST,
                :headers      => Config.headers(),
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onResponse)
        );
    }

    //! makeWebRequest callback.
    //!
    //! Response codes below zero are Connect IQ transport failures rather than
    //! HTTP statuses (-104 no connection, -101 BLE queue full, -300 timeout).
    //! All of them are worth retrying, which is why only an explicit 2xx counts
    //! as delivered.
    //! The parameter types here are not decoration: makeWebRequest type-checks
    //! the callback it is handed, && a looser signature is rejected outright.
    function onResponse(
        responseCode as Lang.Number,
        data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null
    ) as Void {
        var code = responseCode;
        var ok = (code >= 200 && code < 300);
        mLastCode = code;

        if (mDirect != null) {
            EventQueue.recordResult(eventType(mDirect), code, ok);
            if (ok) {
                mDelivered += 1;
            }
            finish();
            return;
        }

        if (mPending == null || mIndex >= mPending.size()) {
            finish();
            return;
        }

        var event = mPending[mIndex] as Lang.Dictionary;
        EventQueue.recordResult(eventType(event), code, ok);

        if (ok) {
            mDelivered += 1;
            mIndex += 1;
            sendNext();
            return;
        }

        // Count the attempt against this event and stop the run, rather than
        // hammering a server that is down or a URL that is wrong. commit()
        // discards it once it has burned through MAX_ATTEMPTS.
        var attempts = event["attempts"];
        event["attempts"] = (attempts == null ? 0 : attempts) + 1;
        finish();
    }

    function delivered() as Lang.Number {
        return mDelivered;
    }

    function lastCode() as Lang.Number {
        return mLastCode;
    }

    //! Strip internal bookkeeping && stamp on the per-attempt metadata.
    hidden function outbound(event as Lang.Dictionary) as Lang.Dictionary {
        var body = {};
        var keys = event.keys();
        for (var i = 0; i < keys.size(); i += 1) {
            var k = keys[i];
            if (!k.equals("attempts")) {
                body[k] = event[k];
            }
        }

        var attempts = event["attempts"];
        body["attempt"] = (attempts == null ? 0 : attempts) + 1;
        body["sent_at"] = Time.now().value();

        return body;
    }

    hidden function eventType(event as Lang.Dictionary) as Lang.String {
        var t = event["event"];
        return t == null ? "unknown" : t.toString();
    }

    //! connectionAvailable rather than phoneConnected: an LTE or Wi-Fi capable
    //! watch can reach the internet with no phone in sight, && gating on the
    //! phone would break exactly those devices.
    hidden function isOnline() as Lang.Boolean {
        var s = System.getDeviceSettings();
        if (s has :connectionAvailable && s.connectionAvailable != null) {
            return s.connectionAvailable;
        }
        if (s has :phoneConnected && s.phoneConnected != null) {
            return s.phoneConnected;
        }
        return true;
    }

    //! Persist whatever is left of the snapshot, exactly once per run, then
    //! hand back to the caller.
    hidden function finish() as Void {
        commit();
        if (mOnDone != null) {
            mOnDone.invoke();
        }
    }

    //! Everything from the cursor onwards survives, minus anything that has
    //! exhausted its attempts. Delivered events are simply left behind.
    hidden function commit() as Void {
        if (mPending == null) {
            return;
        }

        var keep = [];
        for (var i = mIndex; i < mPending.size(); i += 1) {
            var e = mPending[i] as Lang.Dictionary;
            var a = e["attempts"];
            if (a == null || a < EventQueue.MAX_ATTEMPTS) {
                keep.add(e);
            }
        }

        EventQueue.replaceAll(keep);
        mPending = null;
    }
}
