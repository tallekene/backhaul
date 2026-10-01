# Connect IQ Store listing — as submitted

Backhaul 1.0.0, submitted 2026-10-01 under BACKHAUL-6. This is the record of
what went into the form, so the next upload starts from it rather than from
memory. The traps the form springs are in [STORE.md](STORE.md).

## Upload (step 1)

| Field | Value |
|---|---|
| File | `bin/backhaul.iq` from `46c7684`, sha256 `01ccb890…9571`, 236/236 devices |
| App version | 1.0.0 |
| Beta app | no |
| Developer display name | Tallekene (asked once per account; `Tallekene OÜ` is rejected) |

## Details (step 2)

| Field | Value |
|---|---|
| Language | English only |
| Title | Backhaul |
| What's new | — |
| Hero image | — |
| Category | Tools (has no subcategories) |
| Collects user data | Yes |
| Privacy policy URL | https://backhaul.tallekene.com/privacy.html |
| ANT+ profiles | No |
| Regional limits | No |
| Cover image | `art/cover-500x500.png` |
| Device icons | No |
| Screen images | `docs/screenshots/status-fenix7x-280x280.png`, `status-venusq2-320x360.png` |
| Contact email (public) | al@tallekene.com |
| Source code URL | https://github.com/tallekene/backhaul |
| Review notifications | Yes |
| App migration (new compatible devices) | Yes |
| Monetization | No |

## Description

Plain text, no `<` or `>`.

```text
Backhaul needs a server you run yourself. It posts to an HTTPS address you enter in the app settings, and nowhere else. If you do not already have an endpoint that can receive a JSON POST, this app will not do anything useful for you.

Finish an activity and your server hears about it in seconds, rather than whenever your next poll of Garmin Connect happens to run.

EVENTS
- activity.completed: any activity is saved or discarded, including ones recorded by other apps
- goal.reached: a daily step, floors or active-minutes goal is met
- steps.milestone: every 1000 steps (off by default, it is chatty)
- sleep.start / wake: the watch decides you fell asleep or woke up
- heartbeat: a configurable interval, minimum 5 minutes

IT DOES NOT LOSE EVENTS
The activity-completed event arrives the instant you press stop, which is very often the instant your phone is still in a locker on the other side of the building. Backhaul writes undelivered events to device storage and retries them on its next wake-up, for up to 48 hours or 10 delivery attempts, whichever comes first. Time away from the phone costs no attempts. It measures the room it has before each write and drops the oldest event to make room for the newest.

SETUP
Install the app and open it once, then set the webhook URL in Garmin Connect Mobile under your device, then Connect IQ Apps, Backhaul, Settings. It must be https://. Optionally set a bearer token or a custom header so your endpoint can tell your watch apart from the rest of the internet. Back in the app, "Send test event" confirms the round trip.

PRIVACY AND PERMISSIONS
There is no cloud service in the middle, no account and no sign-up. The watch talks to your URL and nobody else's.
- Background: required, so events can fire when the app is not open.
- Communications: required, to POST to your endpoint.
- Location & Tracking: optional and off by default. If you switch it on, events carry a single passive position reading that the watch already has; Backhaul never turns on GPS, so it costs no battery.

OPEN SOURCE
MIT-licensed. Source, payload documentation and a dependency-free example receiver: github.com/tallekene/backhaul

Published by Tallekene OÜ. Garmin and Connect IQ are trademarks of Garmin Ltd. This app is not affiliated with Garmin.
```
