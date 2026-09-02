#!/usr/bin/env bash
# Launch the Connect IQ SDK Manager in a container with an X11 display.
# See the Dockerfile for why this is necessary.
set -euo pipefail

IMAGE=ciq-sdkmanager
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "building $IMAGE ..."
  docker build -t "$IMAGE" "$HERE"
fi

# XWayland listens on the abstract X socket; the container needs permission to
# talk to it. Scoped to local connections only, and revoked on exit.
xhost +local: >/dev/null
trap 'xhost -local: >/dev/null 2>&1 || true' EXIT

docker run --rm -it \
  -e DISPLAY="${DISPLAY:?no DISPLAY set - run this from a graphical session}" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
  -v "$HOME/.Garmin:/home/dev/.Garmin" \
  --user "$(id -u):$(id -g)" \
  "$IMAGE"
