//-----------------------------------------------------------------------------
// Backhaul - https://github.com/laemmlein/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

//! Delivers events, one request at a time.
//!
//! A background process gets a short window to do its work and is killed when
//! it calls Background.exit(), so requests are chained strictly sequentially:
//! the next one is only started from the previous one's callback. Firing them
//! in parallel would overrun the BLE queue (error -101) and lose events.
(:background)
class Dispatcher {

    //! How many events one background wake-up may deliver. The window is short
    //! and each request costs a Bluetooth round trip; the rest keep until the
    //! next temporal event.
    static const MAX_PER_RUN = 5;

    hidden var mOnDone    as Lang.Method or Null;
    hidden var mBudget    as Lang.Number;
    hidden var mDirect    as Lang.Dictionary or Null;
    hidden var mDelivered as Lang.Number;
    hidden var mLastCode  as Lang.Number;

    //! @param onDone Called once when this run is finished, with no arguments.
    //!               In the background that is Background.exit(); in the
    //!               foreground it refreshes the view.
    function initialize(onDone as Lang.Method or Null) {
        mOnDone    = onDone;
        mBudget    = MAX_PER_RUN;
        mDirect    = null;
        mDelivered = 0;
        mLastCode  = 0;
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
        if (!isOnline()) {
            finish();
            return;
        }
        if (mBudget <= 0) {
            finish();
            return;
        }

        var event = EventQueue.peek();
        if (event == null) {
            finish();
            return;
        }

        mBudget -= 1;
        send(event);
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
    function onResponse(code as Lang.Number, data) as Void {
        var ok = (code >= 200 and code < 300);
        mLastCode = code;

        if (mDirect != null) {
            EventQueue.recordResult(eventType(mDirect), code, ok);
            if (ok) {
                mDelivered += 1;
            }
            finish();
            return;
        }

        var head = EventQueue.peek();
        EventQueue.recordResult(head == null ? "unknown" : eventType(head), code, ok);

        if (ok) {
            EventQueue.pop();
            mDelivered += 1;
            drain();
            return;
        }

        // Stop the run on the first failure rather than hammering a server that
        // is down or a URL that is wrong. penaliseHead() counts the attempt and
        // eventually discards an event that can never be delivered.
        EventQueue.penaliseHead();
        finish();
    }

    function delivered() as Lang.Number {
        return mDelivered;
    }

    function lastCode() as Lang.Number {
        return mLastCode;
    }

    //! Strip internal bookkeeping and stamp on the per-attempt metadata.
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
    //! watch can reach the internet with no phone in sight, and gating on the
    //! phone would break exactly those devices.
    hidden function isOnline() as Lang.Boolean {
        var s = System.getDeviceSettings();
        if (s has :connectionAvailable and s.connectionAvailable != null) {
            return s.connectionAvailable;
        }
        if (s has :phoneConnected and s.phoneConnected != null) {
            return s.phoneConnected;
        }
        return true;
    }

    hidden function finish() as Void {
        if (mOnDone != null) {
            mOnDone.invoke();
        }
    }
}
