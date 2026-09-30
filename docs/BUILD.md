# Building Backhaul

## 1. The SDK

Already installed on this machine at
`~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2`
(Connect IQ 9.2.0, released 9 June 2026). To put it on `PATH`:

```bash
. ~/.Garmin/ConnectIQ/env.sh
```

That also exports `CIQ_DEVELOPER_KEY`. Verify with `monkeyc --version`.

### Installing it elsewhere

The SDK zip is a plain download, no account required. Garmin publishes the
version list as JSON, so there is no need to go through the GUI:

```bash
curl -s https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json | jq -r '.[].linux'
curl -LO https://developer.garmin.com/downloads/connect-iq/sdks/<the-linux-zip>
```

Unzip it under `~/.Garmin/ConnectIQ/Sdks/` and `chmod +x` the `bin/`
contents. It needs a Java runtime; Java 21 works.

## 1b. Device definitions — needs a Garmin account

**This is the part that cannot be automated.** The SDK ships compiler,
simulator and docs, but *no* device definitions, and without them
`monkeyc -d fenix7x` fails with `Invalid device id specified`.

Device files come from `api.gcs.garmin.com/ciq-product-onboarding/devices`,
which returns **401** without authentication. The SDK Manager obtains that
token by signing in through `sso.garmin.com` and accepting the SDK
agreement, so a human with a Garmin account has to do it once:

```bash
~/.Garmin/ConnectIQ/sdkmanager/bin/sdkmanager
```

#### On Arch (or anywhere without webkit2gtk-4.0)

The manager links `libwebkit2gtk-4.0` and `libsoup-2.4`. Arch dropped
webkit2gtk-4.0 because it is EOL upstream, and 4.1 cannot stand in for it:
4.1 requires libsoup-3, and libsoup-2 and libsoup-3 cannot coexist in a
single process. Symlinking the newer library aborts at runtime rather than
merely risking ABI drift.

Run it in a container that still has the 4.0 stack instead:

```bash
./tools/sdkmanager-docker/run.sh
```

That builds an Ubuntu 22.04 image on first use, bind-mounts `~/.Garmin` so
downloaded devices land on the host, forwards the X socket (XWayland is
fine), and runs as your uid so the files stay yours.

It is a GUI application and needs a display. Sign in, accept the agreement,
then download the devices you build for — at minimum `fenix7x`. They land
in `~/.Garmin/ConnectIQ/Devices/`, and `monkeyc` picks them up from there
with no further configuration.

Downloading every device is several GB. For day-to-day work install only
the ones you test on; the full set is only needed for an export build of
all 140 targets.

## 2. Developer key

Every build is signed. The key is your identity in the Connect IQ Store: if you
lose it you cannot publish an update to an app you already published, so back it
up somewhere you trust.

One has already been generated at `~/.config/garmin/developer_key.der`. To make
another:

```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

Point the build at a different one with `CIQ_DEVELOPER_KEY=/path/to/key.der`.

## 3. Build

```bash
./build.sh build fenix7x     # a .prg for one device
./build.sh sim   fenix7x     # build and launch it in the simulator
./build.sh export               # the signed .iq bundle for the store
```

Substitute your own device id; the full list is in `manifest.xml`.

`./build.sh sim` runs `connectiq` from the SDK directly, which fails on Arch
with `libwebkit2gtk-4.0.so.37: cannot open shared object file` - the simulator
links the same EOL library as the SDK Manager. Use the container instead:

```bash
./tools/sdkmanager-docker/sim.sh start
./tools/sdkmanager-docker/sim.sh run bin/backhaul.prg fenix7x
./tools/sdkmanager-docker/sim.sh logs
./tools/sdkmanager-docker/sim.sh stop
```

The prg has to live under the project directory, because that is what the
container mounts. Two further limits, both found the hard way: the simulator
accepts only one `run` per container lifetime, so restart it between tests, and
the simulator opens on the *glance* view for an app that has one - you have to
press START on the device to reach the app itself, which no amount of `xdotool`
will do for you, because the compositor will not hand focus to the XWayland
window.

## 4. Run it on the watch

A sideloaded app has no settings page in Garmin Connect Mobile, so its
defaults are its configuration. Put the ones you need in
`~/.config/backhaul/sideload.env` (or set `BACKHAUL_SIDELOAD_ENV`), one
`property_id=value` per line, ids as in `resources/settings/properties.xml`:

```
webhook_url=https://example.org/webhook/backhaul
auth_token=<token>
```

`./build.sh build` bakes these into a staged copy of the source, so they never
reach the repository. Keep the file mode 600. `sim` builds ignore it, so
simulator events never reach the real endpoint.

Sideloading, no store account needed:

1. Connect the watch by USB. It mounts as mass storage.
2. Copy `bin/backhaul.prg` into `GARMIN/APPS/` on the device.
3. Eject, and the app appears in the app list.

## 4b. Two things sideloading does that will confuse you

**The .prg disappears.** The watch ingests a sideloaded app into internal
storage and deletes the file, so `GARMIN/Apps/` ends up with no `.prg` in
it at all - not yours, not any of your other Connect IQ apps. That is a
successful install, not a failed one. Each new build must be copied across
again.

**Stored settings beat new defaults.** The first time the app runs, the
watch writes `GARMIN/Apps/SETTINGS/<APPNAME>.SET` holding the values in
force at that moment. From then on that file wins. Changing a default in
`properties.xml` and reinstalling therefore appears to do nothing - the
app keeps reading the old stored value. Delete the `.SET` file to make the
new defaults take effect:

```bash
rm "<mountpoint>/Internal Storage/GARMIN/Apps/SETTINGS/BACKHAUL.SET"
```

This matters more than usual here because a sideloaded app has no settings
UI at all (see 1b), so baked-in defaults are the only way to configure it.

## 5. Open the app once

This is the step everyone misses. Background events are registered by the
*foreground* app, so nothing is sent until you have opened Backhaul at least
once after installing it or changing which events are enabled. The status screen
turning green is the confirmation.

## Testing without a watch

The simulator can fake the events:

- **Simulation → Trigger Background Event** in the simulator menu fires the
  temporal, activity-completed and goal events on demand.
- **Settings → Edit Application Settings** (or the "App Settings" toolbar
  button) edits the same properties the phone would.
- The simulator will happily talk to `http://localhost` — a real watch will not.
  Point it at `examples/receiver.py` and watch the deliveries land.

## Things that go wrong

| Symptom | Cause |
|---|---|
| Nothing is ever sent | The app has not been opened since the settings changed. |
| Response code `-104` | No connection: phone out of range, or Bluetooth off. |
| Response code `-101` | BLE queue full — something else is hammering the link. |
| Response code `-403` | Response too large for the watch. Return a short body. |
| Works in the simulator, not on the watch | Almost always `http://` instead of `https://`, or a certificate the watch will not accept. |
| A device target fails to compile on `GlanceView` | That device has no glance support; drop it from `manifest.xml`. |
