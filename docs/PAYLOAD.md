# Webhook payload

Every event is a single `POST` with a JSON body and `Content-Type:
application/json`. Nothing is ever sent as a query parameter.

## Envelope

```json
{
  "schema": 1,
  "event": "activity.completed",
  "id": "activity.completed-1772668800-04213",
  "ts": 1772668800,
  "sent_at": 1772669100,
  "attempt": 2,
  "device": { },
  "data": { },
  "health": { },
  "location": { }
}
```

| Field | Always present | Meaning |
|---|---|---|
| `schema` | yes | Payload version. Bumped only for a breaking change. |
| `event` | yes | Event type, see below. |
| `id` | yes | Stable across retries of the same event. **Deduplicate on this.** |
| `ts` | yes | When the event happened on the watch, Unix seconds UTC. |
| `sent_at` | yes | When *this delivery attempt* was made. |
| `attempt` | yes | 1 on first try, higher when it came out of the retry queue. |
| `device` | yes | Which watch, and what state it was in. |
| `data` | per event | Event-specific fields. Absent for events that carry none. |
| `health` | if enabled | Steps, heart rate and friends. |
| `location` | if enabled | Position, if the watch had a fix. |

`ts` and `sent_at` differ when the event was queued: the watch was offline when
it happened and only delivered it later. `sent_at - ts` is how long that took.

## Event types

| `event` | Trigger | `data` |
|---|---|---|
| `activity.completed` | An activity was saved or discarded, including ones recorded by other apps | `sport`, `sport_name`, `sub_sport`, `sub_sport_name` |
| `goal.reached` | A daily goal was met | `goal`, `goal_name` (`steps`, `floors_climbed`, `active_minutes`) |
| `steps.milestone` | Every 1000 steps | `steps` |
| `sleep.start` | Watch detected sleep | — |
| `wake` | Watch detected wake | — |
| `heartbeat` | The configured interval elapsed | — |
| `test` | "Send test event" in the app menu | — |

`sport` and `sub_sport` are the raw FIT enumeration integers. `sport_name` is a
convenience mapping that covers the common values and falls back to `sport_<n>`
for anything it does not know — **map the integer yourself if correctness
matters**, the name is there so a dashboard has something to show.

## `device`

```json
{
  "label": "fenix 8",
  "part_number": "006-B4432-00",
  "ciq_version": "5.1.1",
  "phone_connected": true,
  "battery": 71.5,
  "charging": false
}
```

`label` is whatever you typed in the settings, and is the only way to tell two
of your own watches apart — Connect IQ does not expose a device serial.

## `health`

Only when *Include steps and heart rate* is on. Keys are omitted rather than
sent as null when the watch has no value, so a missing key means "no reading",
not "zero".

```json
{
  "steps": 8421,
  "step_goal": 9000,
  "calories": 2210,
  "distance_cm": 615300,
  "floors_climbed": 12,
  "floors_goal": 10,
  "active_minutes": 47,
  "heart_rate": 58
}
```

`heart_rate` is frequently absent outside an activity: the optical sensor is
duty-cycled and there may be no recent sample.

## `location`

Only when *Include location* is on, and only when the watch had a fix.

```json
{
  "quality": "good",
  "lat": 48.137,
  "lon": 11.575,
  "altitude_m": 519,
  "speed_mps": 0.0,
  "heading_deg": 271
}
```

`quality` is one of `good`, `usable`, `poor`, `last_known`. Garmin gives four
buckets and no error estimate, so this app reports the bucket rather than
inventing a metre figure you would be tempted to do arithmetic on.

## What your endpoint must do

- **Answer quickly.** The watch is holding a Bluetooth link open and its
  background process has seconds to live. Acknowledge first, then do the work.
- **Return 2xx on success.** Anything else — including 3xx — is treated as a
  failure and the event is retried.
- **Expect duplicates.** If your `200` never makes it back across Bluetooth, the
  watch retries an event you already handled. `id` is stable so you can spot it.
- **Expect events out of order.** A queue drain delivers backlog before the
  event that triggered the drain.
- **Use HTTPS.** Connect IQ will not make plaintext requests from a device.

## Failure handling on the watch

| Response | Watch behaviour |
|---|---|
| `2xx` | Delivered, dropped from the queue |
| `4xx` / `5xx` | Attempt counted, retried at the next interval |
| Negative code | Transport failure (`-104` no connection, `-101` BLE queue full, `-300` timeout); retried |

An event is discarded after 10 failed attempts or 48 hours, whichever comes
first, so one permanently undeliverable payload cannot wedge the queue behind
it.
