#!/usr/bin/env bash
# Run the simulator on a virtual X display so it can be driven by script - the
# way the store screenshots were taken. See Dockerfile.headless for why sim.sh's
# windowed simulator cannot be.
#
#   ./sim-headless.sh start                start the simulator on Xvfb
#   ./sim-headless.sh run <prg> [device]   side-load a prg (blocks; background it)
#   ./sim-headless.sh shot <out.png>       grab the whole simulator window
#   ./sim-headless.sh xdo <xdotool args>   drive it, e.g. xdo key Up
#   ./sim-headless.sh stop
#
# Paths are relative to the project directory, which is what the container
# mounts. With no window manager, windowactivate fails; xdo uses windowfocus.
# That is not enough for keys: they only reach the simulator once a click on
# the watch *screen* has given its canvas focus (a click on the strap does not).
# On a fenix 7X that is `xdo mousemove 220 300 click 1`; on a touchscreen device
# the same click is also a tap the app receives.
#
# Two traps. The simulator opens an app that has a glance on the glance, and
# START does not open the app from there, so a screenshot of the app's own view
# needs a build without getGlanceView(). And File > Save Screen Capture is the
# only way to get the raw framebuffer without the watch bezel: drive its GTK
# save dialog by typing an absolute /project/... path into the Name field.
set -euo pipefail

BASE=ciq-sdkmanager
IMAGE=ciq-sim-headless
NAME=ciq-sim-x
X=:99
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/../.." && pwd)"
SDK_BIN='/home/dev/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin'

case "${1:-start}" in
  start)
    docker image inspect "$BASE"  >/dev/null 2>&1 || docker build -t "$BASE" "$HERE"
    docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -t "$IMAGE" -f "$HERE/Dockerfile.headless" "$HERE"
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" \
      -e HOME=/home/dev -e DISPLAY="$X" \
      -v "$HOME/.Garmin:/home/dev/.Garmin" \
      -v "$PROJECT:/project" \
      --user "$(id -u):$(id -g)" \
      --entrypoint bash "$IMAGE" \
      -c "Xvfb $X -screen 0 1400x1100x24 >/tmp/xvfb.log 2>&1 & sleep 4; exec $SDK_BIN/simulator" >/dev/null
    echo "headless simulator started as container '$NAME' on $X"
    ;;
  run)
    docker exec -e DISPLAY="$X" "$NAME" "$SDK_BIN/monkeydo" "/project/${2:?prg path}" "${3:-fenix7x}"
    ;;
  shot)
    docker exec -e DISPLAY="$X" "$NAME" sh -c \
      'import -window "$(xdotool search --name "CIQ Simulator" | head -1)" "/project/$0"' "${2:?output path}"
    ;;
  xdo)
    shift
    docker exec -e DISPLAY="$X" "$NAME" sh -c \
      'xdotool windowfocus --sync "$(xdotool search --name "CIQ Simulator" | head -1)" && xdotool "$@"' xdo "$@"
    ;;
  stop) docker rm -f "$NAME" >/dev/null 2>&1; echo stopped ;;
  *)    echo "usage: $0 {start|run|shot|xdo|stop}" >&2; exit 2 ;;
esac
