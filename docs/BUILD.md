# Building Backhaul

## 1. The SDK

The Connect IQ SDK is not packaged anywhere sensible; you get it from Garmin.

1. Sign in at <https://developer.garmin.com/connect-iq/sdk/> and download the
   **SDK Manager** for Linux.
2. Run it, accept the licence, and install the latest SDK plus the device
   definitions you care about. Device definitions are downloaded per device and
   the full set is several GB — for day-to-day work just install yours.
3. Put the SDK's `bin` on your `PATH`:

   ```bash
   export PATH="$HOME/.Garmin/ConnectIQ/Sdks/<sdk-version>/bin:$PATH"
   ```

   `monkeyc`, `monkeydo` and `connectiq` should then resolve.

The SDK needs a Java runtime. `java` is already present on this machine.

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

## 4. Run it on the watch

Sideloading, no store account needed:

1. Connect the watch by USB. It mounts as mass storage.
2. Copy `bin/backhaul.prg` into `GARMIN/APPS/` on the device.
3. Eject, and the app appears in the app list.

Settings for a sideloaded app are edited in **Garmin Connect Mobile → your
device → Connect IQ Apps → Backhaul → Settings**, exactly as for a store app.

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
