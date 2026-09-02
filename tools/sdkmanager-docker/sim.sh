#!/usr/bin/env bash
# Run the Connect IQ simulator (and monkeydo) inside the container, for the same
# reason the SDK Manager needs it: the simulator links webkit2gtk-4.0, which
# modern Arch does not ship.
#
#   ./sim.sh start          launch the simulator window
#   ./sim.sh run <prg> <device>   side-load a prg into the running simulator
#   ./sim.sh logs           show simulator/app console output
#   ./sim.sh stop
#
# Note: the simulator reliably accepts only ONE `run` per container lifetime.
# Subsequent monkeydo invocations hang with no output and no error. Restart it
# between runs when scripting tests:
#
#   ./sim.sh stop && ./sim.sh start && sleep 12 && ./sim.sh run ...
#
# Also: drive a test from a Timer after the view is up, not from onStart. A web
# request issued during onStart is silently dropped and its callback never
# fires, which looks identical to a hang.
set -euo pipefail

IMAGE=ciq-sdkmanager
NAME=ciq-sim
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/../.." && pwd)"
SDK_BIN='/home/dev/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin'

case "${1:-start}" in
  start)
    docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -t "$IMAGE" "$HERE"
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    xhost +local: >/dev/null
    docker run -d --name "$NAME" \
      -e DISPLAY="${DISPLAY:?no DISPLAY}" -e HOME=/home/dev \
      -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
      -v "$HOME/.Garmin:/home/dev/.Garmin" \
      -v "$PROJECT:/project" \
      --user "$(id -u):$(id -g)" \
      --entrypoint "$SDK_BIN/simulator" \
      "$IMAGE" >/dev/null
    echo "simulator started as container '$NAME'"
    ;;
  run)
    docker exec "$NAME" "$SDK_BIN/monkeydo" "/project/${2:-bin/backhaul.prg}" "${3:-fenix7x}"
    ;;
  logs)   docker logs --tail "${2:-60}" "$NAME" ;;
  stop)   docker rm -f "$NAME" >/dev/null 2>&1; xhost -local: >/dev/null 2>&1 || true; echo stopped ;;
  *)      echo "usage: $0 {start|run|logs|stop}" >&2; exit 2 ;;
esac
