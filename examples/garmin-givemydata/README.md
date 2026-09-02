# Wiring Backhaul into garmin-givemydata

Turns "activity finished" into "sync now" instead of waiting out the rest of a
900-second sleep. Worst-case latency from pressing stop to the data being in
Postgres drops from ~15 minutes (plus the pg-sync interval) to roughly however
long the fetch itself takes.

**Nothing here has been applied.** These are the two changes it needs, ready to
review. They touch a live gitops repo and a running deployment, so they are
yours to land.

## How it fits

The sync container is a `while true; do fetch; sleep 900; done` loop with no way
in. Three pieces:

1. **`loop_sync.sh`** learns an interruptible sleep: it wakes early if a trigger
   file appears on the shared PVC. See `loop_sync.patch`.
2. **A `trigger` sidecar** in the same pod runs `receiver.py` and writes that
   file. It has to be in the same pod, not a separate Deployment, because the
   PVC is RWO and already mounted by that pod. See `deployment-patch.yaml`.
3. **An Ingress** exposes the receiver over HTTPS. The watch will not make
   plaintext requests, and it needs a certificate the watch trusts — a public
   Let's Encrypt cert, not the internal CA.

## The mTLS problem

The cluster's ingress is behind mTLS, and a Garmin watch cannot present a client
certificate. This endpoint has to be reachable without one, which means:

- a dedicated hostname with mTLS disabled for that host only, and
- the bearer token doing the actual authentication.

That is a deliberate hole in an otherwise mTLS-only perimeter for a single POST
endpoint. The receiver only ever touches a file on a PVC, and the token is
checked in constant time, but it is still a decision worth making consciously
rather than discovering later.

An alternative that avoids the hole entirely: point the watch at a small public
endpoint you already run and have *it* poke the cluster over the existing mesh.
Costs a hop, keeps the perimeter intact.

## Sealed secret

The bearer token needs to exist as a Secret before the sidecar starts:

```bash
kubectl create secret generic backhaul-token \
  --namespace personal-data \
  --from-literal=token="$(openssl rand -hex 32)" \
  --dry-run=client -o yaml | kubeseal --format yaml > SealedSecret.backhaul-token.yaml
```

Mind the kubeseal here-string trailing-newline trap — build the literal with
`--from-literal`, as above, rather than piping.

The same value goes into the watch's **Bearer token** setting.
