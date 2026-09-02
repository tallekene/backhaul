#!/usr/bin/env bash
# Build, run or export Backhaul.
#
#   ./build.sh sim   [device]   build and launch in the simulator
#   ./build.sh build [device]   build a .prg for sideloading
#   ./build.sh export           build the .iq bundle for the Connect IQ Store
#
# Needs the Connect IQ SDK on PATH (monkeyc/monkeydo) and a developer key.
# See docs/BUILD.md for both.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="${2:-fenix7x}"
KEY="${CIQ_DEVELOPER_KEY:-$HOME/.config/garmin/developer_key.der}"
OUT="$ROOT/bin"

if ! command -v monkeyc >/dev/null; then
  echo "monkeyc not on PATH. Install the Connect IQ SDK - see docs/BUILD.md" >&2
  exit 1
fi

if [ ! -f "$KEY" ]; then
  echo "No developer key at $KEY. Create one - see docs/BUILD.md" >&2
  exit 1
fi

mkdir -p "$OUT"

case "${1:-build}" in
  build|sim)
    monkeyc -f "$ROOT/monkey.jungle" -d "$DEVICE" -o "$OUT/backhaul.prg" -y "$KEY" --warn
    echo "built $OUT/backhaul.prg for $DEVICE"
    if [ "${1}" = "sim" ]; then
      # connectiq starts the simulator; it is a no-op if one is already up.
      connectiq &
      sleep 3
      monkeydo "$OUT/backhaul.prg" "$DEVICE"
    fi
    ;;
  export)
    # -e builds every device in the manifest into one signed .iq bundle. This
    # is the file the store wants, and it is also the slow one: expect minutes.
    monkeyc -f "$ROOT/monkey.jungle" -e -o "$OUT/backhaul.iq" -y "$KEY" --warn
    echo "built $OUT/backhaul.iq"
    ;;
  *)
    echo "usage: $0 {build|sim|export} [device]" >&2
    exit 2
    ;;
esac
