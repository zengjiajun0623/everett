#!/usr/bin/env bash
# Chain liveness alarm: shout when Wheeler stops producing blocks.
#
# Why this exists: on 2026-08-14 the GPU miner wedged (hashing at 100% but
# submitting nothing) and the chain sat at the same height for 27 minutes
# before a human happened to notice an odd number. Nothing alarmed, because
# every existing check watches CORRECTNESS, not LIVENESS: burn_audit still
# said PASS, the gates were green, the dashboard rendered fine. A stalled
# chain is not an invalid chain, so a correctness monitor is blind to it.
#
# Alarms on either of:
#   - the node's RPC is unreachable
#   - the head block is older than STALL_SECONDS
#
# At the 13s target, a 300s gap is about 23 missed blocks; the probability
# of that happening by chance is around e^-23, so this does not fire on
# variance. It fires on something being broken.
#
# One message per episode (a sentinel file), and one recovery message when
# blocks resume, because an alarm that repeats every minute trains you to
# ignore it.
set -uo pipefail
EVERETT="$(cd "$(dirname "$0")/.." && pwd)"
RPC="${RPC:-http://127.0.0.1:8545}"
STALL_SECONDS="${STALL_SECONDS:-300}"
SENTINEL="$EVERETT/build/chain-stalled"
LOG="$EVERETT/build/liveness.log"
PHONE="${EVERETT_ALERT_PHONE:-+16692137336}"

mkdir -p "$EVERETT/build"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

notify() {
  # iMessage, the established escalation path for this project. Failures
  # only: no status pings, or the channel stops meaning anything.
  osascript -e "tell application \"Messages\" to send \"$1\" to buddy \"$PHONE\" of (service 1 whose service type is iMessage)" \
    >/dev/null 2>&1 || log "WARN: could not send iMessage (Messages not signed in?)"
}

HEAD_JSON=$(curl -s -m 10 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_getBlockByNumber","params":["latest",false]}' \
  "$RPC" 2>/dev/null || true)

if [ -z "$HEAD_JSON" ] || ! echo "$HEAD_JSON" | grep -q '"number"'; then
  if [ ! -f "$SENTINEL" ]; then
    echo "rpc-unreachable $(date +%s)" > "$SENTINEL"
    log "ALARM: node RPC unreachable at $RPC"
    notify "Everett ALARM: the Wheeler node's RPC is unreachable at $RPC. The chain may be down."
  else
    log "still unreachable"
  fi
  exit 0
fi

read -r HEIGHT AGE <<EOF
$(echo "$HEAD_JSON" | python3 -c "
import json, sys, time
b = json.load(sys.stdin)['result']
print(int(b['number'], 16), int(time.time()) - int(b['timestamp'], 16))
")
EOF

if [ "$AGE" -gt "$STALL_SECONDS" ]; then
  if [ ! -f "$SENTINEL" ]; then
    echo "stalled $(date +%s) height=$HEIGHT" > "$SENTINEL"
    log "ALARM: no new block for ${AGE}s (head $HEIGHT)"
    notify "Everett ALARM: Wheeler has not produced a block in $((AGE / 60)) min (head $HEIGHT). Usual cause: the GPU miner wedged. Fix: ssh pc3080 'schtasks /end /tn WheelerGPU' then '/run /tn WheelerGPU'."
  else
    log "still stalled: ${AGE}s at height $HEIGHT"
  fi
elif [ -f "$SENTINEL" ]; then
  rm -f "$SENTINEL"
  log "RECOVERED: block $HEIGHT is ${AGE}s old"
  notify "Everett recovered: blocks are landing again (head $HEIGHT)."
else
  log "ok: height $HEIGHT, ${AGE}s old"
fi
