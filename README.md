# Backhaul

Send a webhook from your Garmin watch when something happens on it.

Finish an activity and your server hears about it in seconds, rather than
whenever your next poll of Garmin Connect happens to run. Also fires on daily
goals, step milestones, sleep and wake, plus an optional heartbeat.

No cloud service in the middle, no account, no Garmin Developer Program
application. The watch talks to your URL and nobody else's.

## Events

| Event | When |
|---|---|
| `activity.completed` | Any activity is saved or discarded — including ones recorded by other apps |
| `goal.reached` | A daily step, floors or active-minutes goal is met |
| `steps.milestone` | Every 1000 steps (off by default — it is chatty) |
| `sleep.start` / `wake` | The watch decides you fell asleep or woke up |
| `heartbeat` | A configurable interval, minimum 5 minutes |

Payloads are documented in [docs/PAYLOAD.md](docs/PAYLOAD.md).

## It does not lose events

The activity-completed event arrives the instant you press stop, which is very
often the instant your phone is still in a locker on the other side of the
building. Backhaul writes undelivered events to device storage and retries them
on its next wake-up, for up to 48 hours or 10 delivery attempts, whichever comes
first. Time away from the phone costs no attempts, so a watch that simply cannot
reach anything keeps its events for the full two days; the attempt limit is what
stops one unreachable endpoint retrying forever.

This is the thing that separates it from wiring the same event up by hand: the
naive version drops exactly the events you most wanted.

## Setup

1. Install the app and open it once. (Background events are registered by the
   foreground app — until you open it, nothing is armed.)
2. In Garmin Connect Mobile → your device → Connect IQ Apps → Backhaul →
   Settings, set the **Webhook URL**. It must be `https://`.
3. Optionally set a **Bearer token** or a custom header so your endpoint can
   tell your watch apart from the rest of the internet.
4. Pick which events you want.
5. Back in the app, **Send test event** from the menu to confirm the round trip.

The status screen shows green when it is armed, how many events are queued, and
how the last delivery went.

## Receiving

`examples/receiver.py` is a dependency-free receiver that checks the token,
drops duplicate deliveries and runs a shell command per event type:

```bash
BACKHAUL_TOKEN=changeme ./examples/receiver.py --port 8099 \
    --on-activity 'touch /data/.sync-now'
```

Put it behind whatever TLS terminator you already run — the watch will not make
plaintext requests.

## Building

See [docs/BUILD.md](docs/BUILD.md). Short version: install the Connect IQ SDK,
then `./build.sh sim fenix7x`.

## Device support

140 devices, everything from a fēnix 5 to a Venu X1. Requires Connect IQ 3.1.0.

Two capabilities degrade rather than exclude a device:

- **Offline queueing** needs Connect IQ 3.2.0 to reach storage from a background
  process. Below that the app delivers or drops, and says so on screen.
- **Background services** are unavailable on a handful of older watches. The
  app detects this and reports "Not supported" instead of pretending to work.

How deep the queue goes also depends on the device. Garmin gives a background
process 64 KB on newer watches and 32 KB on older ones, which works out at the
full 25 events on a fēnix 7X and around four on a fēnix 6 Pro. The app measures
the room it has before each write rather than assuming, and when it runs out it
drops the oldest event to make room for the newest.

## Licence

MIT. See [LICENSE](LICENSE).
