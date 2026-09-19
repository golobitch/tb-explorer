#!/bin/bash
# Ensures a seeded single-replica TigerBeetle dev cluster is running.
#
# Idempotent: exits immediately if the address is already listening. Otherwise it
# downloads the pinned binary and formats the data file if needed, starts the
# replica detached (it keeps running after Xcode stops the app), and seeds it when
# the data file was just created.
#
# Used by the TBExplorer scheme's Run and Test pre-actions and by `make tb-up`.
# Xcode discards pre-action output, so the scheme redirects it to
# .tigerbeetle/dev-cluster.log.
set -euo pipefail

# Xcode exports SWIFT_* build settings into pre-actions; the Swift runtime in system
# tools and tb-seed warns about each one, cluttering the log.
unset $(compgen -v SWIFT_) 2>/dev/null || true

# Derived from this script rather than SRCROOT, which Xcode sets to ui/, not the repo root.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADDR="${TB_ADDR:-127.0.0.1:3000}"
HOST="${ADDR%:*}"
PORT="${ADDR##*:}"
DATA=".tigerbeetle/0_0.tigerbeetle"
SEED="${BUILT_PRODUCTS_DIR:-$ROOT/build/DerivedData/Build/Products/Debug}/tb-seed"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

cd "$ROOT"
mkdir -p .tigerbeetle

if nc -z "$HOST" "$PORT" 2>/dev/null; then
    log "cluster already listening on $ADDR"
    exit 0
fi

if lsof -t "$DATA" >/dev/null 2>&1; then
    log "$DATA is held by another replica (not on $ADDR); stop it with: make tb-stop"
    exit 1
fi

fresh=0
[ -f "$DATA" ] || fresh=1

make -s tb-format TB_DATA="$DATA"

log "starting replica on $ADDR"
nohup .bin/tigerbeetle start --addresses="$ADDR" --development "$DATA" \
    >> .tigerbeetle/server.log 2>&1 < /dev/null &
disown || true

for _ in $(seq 1 120); do
    nc -z "$HOST" "$PORT" 2>/dev/null && break
    sleep 0.5
done
if ! nc -z "$HOST" "$PORT" 2>/dev/null; then
    log "replica did not start; see .tigerbeetle/server.log"
    exit 1
fi
log "replica listening on $ADDR"

if [ "$fresh" = 1 ]; then
    if [ -x "$SEED" ]; then
        log "seeding new data file"
        "$SEED" --addresses "$ADDR"
    else
        log "new data file is empty and tb-seed is not built yet; run: make seed"
    fi
fi
