#!/usr/bin/env python3
"""A minimal Backhaul receiver.

Standard library only, so it runs anywhere Python does:

    BACKHAUL_TOKEN=changeme ./receiver.py --port 8099 \
        --on-activity 'touch /data/.sync-now'

It verifies the bearer token, drops duplicate deliveries, and runs a shell
command per event type. That is enough to turn "activity finished on the watch"
into "kick the thing that ingests it" without pulling in a web framework.

Not intended to face the internet unprotected: put it behind whatever TLS
terminator you already run, since the watch will only talk to https.
"""

import argparse
import hmac
import json
import logging
import os
import subprocess
import sys
import threading
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = logging.getLogger("backhaul")

# Deliveries can repeat: the watch retries anything whose response it did not
# see, which includes requests we handled perfectly and then failed to ack
# because the phone wandered out of Bluetooth range. Dedupe on the event id.
SEEN_LIMIT = 500
_seen: "OrderedDict[str, None]" = OrderedDict()
_seen_lock = threading.Lock()


def already_seen(event_id: str) -> bool:
    with _seen_lock:
        if event_id in _seen:
            return True
        _seen[event_id] = None
        while len(_seen) > SEEN_LIMIT:
            _seen.popitem(last=False)
        return False


class Handler(BaseHTTPRequestHandler):
    server_version = "backhaul-receiver/1.0"
    actions: "dict[str, str]" = {}
    token: "str | None" = None

    def log_message(self, fmt, *args):  # quieter default access log
        LOG.debug("%s - %s", self.address_string(), fmt % args)

    def _reply(self, code: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _authorised(self) -> bool:
        if not self.token:
            return True
        supplied = self.headers.get("Authorization", "")
        prefix = "Bearer "
        if not supplied.startswith(prefix):
            return False
        # compare_digest rather than ==, so a wrong token cannot be recovered
        # one character at a time from response timings.
        return hmac.compare_digest(supplied[len(prefix):], self.token)

    def do_GET(self):
        if self.path == "/healthz":
            self._reply(200, {"ok": True})
        else:
            self._reply(404, {"error": "not found"})

    def do_POST(self):
        if not self._authorised():
            LOG.warning("rejected unauthorised delivery from %s", self.address_string())
            self._reply(401, {"error": "unauthorised"})
            return

        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > 65536:
            self._reply(400, {"error": "bad length"})
            return

        try:
            event = json.loads(self.rfile.read(length))
        except (ValueError, UnicodeDecodeError) as exc:
            LOG.warning("undecodable body: %s", exc)
            self._reply(400, {"error": "bad json"})
            return

        kind = str(event.get("event", "unknown"))
        event_id = str(event.get("id", ""))
        attempt = event.get("attempt", 1)

        if event_id and already_seen(event_id):
            LOG.info("duplicate %s (%s), attempt %s - acking without acting",
                     kind, event_id, attempt)
            self._reply(200, {"ok": True, "duplicate": True})
            return

        LOG.info("%s id=%s attempt=%s battery=%s queued_age=%ss",
                 kind, event_id, attempt,
                 (event.get("device") or {}).get("battery"),
                 age_seconds(event))
        LOG.debug("payload: %s", json.dumps(event, sort_keys=True))

        # Ack before acting. The watch is holding a Bluetooth connection open
        # and its background process has seconds to live, so a slow handler
        # here turns into a lost event there.
        self._reply(200, {"ok": True})
        self.run_action(kind, event)

    def run_action(self, kind: str, event: dict) -> None:
        command = self.actions.get(kind) or self.actions.get("*")
        if not command:
            return

        env = dict(os.environ)
        env["BACKHAUL_EVENT"] = kind
        env["BACKHAUL_JSON"] = json.dumps(event)
        data = event.get("data") or {}
        if isinstance(data, dict):
            for key, value in data.items():
                env["BACKHAUL_" + str(key).upper()] = str(value)

        try:
            result = subprocess.run(command, shell=True, env=env, timeout=60,
                                    capture_output=True, text=True)
        except subprocess.TimeoutExpired:
            LOG.error("action for %s timed out", kind)
            return

        if result.returncode != 0:
            LOG.error("action for %s exited %s: %s",
                      kind, result.returncode, result.stderr.strip())
        else:
            LOG.info("action for %s ok", kind)


def age_seconds(event: dict):
    """How long the event sat on the watch before it reached us."""
    ts, sent = event.get("ts"), event.get("sent_at")
    if isinstance(ts, int) and isinstance(sent, int):
        return sent - ts
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8099)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--on-activity", metavar="CMD",
                        help="shell command to run on activity.completed")
    parser.add_argument("--on-goal", metavar="CMD")
    parser.add_argument("--on-any", metavar="CMD",
                        help="fallback command for every other event type")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
    )

    Handler.token = os.environ.get("BACKHAUL_TOKEN")
    if not Handler.token:
        LOG.warning("BACKHAUL_TOKEN is unset - accepting unauthenticated deliveries")

    Handler.actions = {
        k: v for k, v in (
            ("activity.completed", args.on_activity),
            ("goal.reached", args.on_goal),
            ("*", args.on_any),
        ) if v
    }

    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    LOG.info("listening on %s:%s", args.bind, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        LOG.info("shutting down")
    return 0


if __name__ == "__main__":
    sys.exit(main())
