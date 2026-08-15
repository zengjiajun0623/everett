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
RESTARTS="$EVERETT/build/miner-restarts"   # timestamps of auto-restarts
LOG="$EVERETT/build/liveness.log"
# Auto-remediation is deliberately BOUNDED. The one failure this has seen
# (2026-08-14) was the GPU miner wedging: hashing at 100% while submitting
# nothing, cleared instantly by restarting its scheduled task. Restarting
# it automatically turns a 27-minute outage into a 2-minute one.
#
# But a self-healing loop that silently papers over a recurring fault is
# worse than the outage, because the frequency never reaches a human. So:
# at most one restart per stall episode, and at most MAX_RESTARTS within
# RESTART_WINDOW before it stops trying and escalates instead.
AUTO_RESTART="${AUTO_RESTART:-1}"
MAX_RESTARTS="${MAX_RESTARTS:-3}"
RESTART_WINDOW="${RESTART_WINDOW:-21600}"   # 6 hours
PHONE="${EVERETT_ALERT_PHONE:-+16692137336}"

mkdir -p "$EVERETT/build"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

notify() {
  # iMessage, the established escalation path for this project. Failures
  # only: no status pings, or the channel stops meaning anything.
  osascript -e "tell application \"Messages\" to send \"$1\" to buddy \"$PHONE\" of (service 1 whose service type is iMessage)" \
    >/dev/null 2>&1 || log "WARN: could not send iMessage (Messages not signed in?)"
}

# Record who is connected, while they are still connected. Peer identity
# lives only in a live admin_peers call -- the node logs "peercount=N" and
# nothing else -- so a peer that disconnects is unidentifiable forever
# after. This rides along because this script already polls once a minute.
#
# Failure here must never touch the alarm: a ledger is a nice-to-have, a
# stalled chain is not. Hence the guard and the discarded exit status.
[ "${PEER_LEDGER_ENABLED:-1}" = "1" ] && \
  python3 "$EVERETT/scripts/peer_ledger.py" >> "$LOG" 2>&1 || true

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

restart_miner() {
  # Count restarts inside the window; drop older ones.
  local now cutoff recent=0
  now=$(date +%s); cutoff=$((now - RESTART_WINDOW))
  if [ -f "$RESTARTS" ]; then
    awk -v c="$cutoff" '$1 > c' "$RESTARTS" > "$RESTARTS.tmp" && mv "$RESTARTS.tmp" "$RESTARTS"
    recent=$(wc -l < "$RESTARTS" | tr -d ' ')
  fi
  if [ "$recent" -ge "$MAX_RESTARTS" ]; then
    log "NOT auto-restarting: $recent restarts already in the last $((RESTART_WINDOW / 3600))h"
    notify "Everett ALARM: Wheeler stalled again and the miner has already been auto-restarted $recent times in $((RESTART_WINDOW / 3600))h. Not restarting again: something is recurring and wants a human. Check nvidia-smi and kawpowminer/wheeler.err on pc3080."
    return 1
  fi
  log "auto-restarting the GPU miner (restart $((recent + 1)) of $MAX_RESTARTS in window)"
  if ssh -o ConnectTimeout=10 -o BatchMode=yes pc3080 "schtasks /end /tn WheelerGPU" >/dev/null 2>&1 &&
     ssh -o ConnectTimeout=10 -o BatchMode=yes pc3080 "schtasks /run /tn WheelerGPU" >/dev/null 2>&1; then
    echo "$now" >> "$RESTARTS"
    notify "Everett: Wheeler stalled ($((AGE / 60)) min, head $HEIGHT); auto-restarted the GPU miner. Will alarm if blocks do not resume."
    return 0
  fi
  log "auto-restart FAILED (ssh to pc3080 unreachable?)"
  notify "Everett ALARM: Wheeler stalled ($((AGE / 60)) min, head $HEIGHT) and the automatic miner restart FAILED. pc3080 may be unreachable."
  return 1
}

if [ "$AGE" -gt "$STALL_SECONDS" ]; then
  if [ ! -f "$SENTINEL" ]; then
    echo "stalled $(date +%s) height=$HEIGHT" > "$SENTINEL"
    log "ALARM: no new block for ${AGE}s (head $HEIGHT)"
    if [ "$AUTO_RESTART" = "1" ]; then
      restart_miner || true
    else
      notify "Everett ALARM: Wheeler has not produced a block in $((AGE / 60)) min (head $HEIGHT). Usual cause: the GPU miner wedged. Fix: ssh pc3080 'schtasks /end /tn WheelerGPU' then '/run /tn WheelerGPU'."
    fi
  else
    # Already alarmed and (probably) restarted once for this episode. If it
    # is STILL stalled well past the restart, the restart did not work and a
    # human is needed.
    STARTED=$(awk '{print $2}' "$SENTINEL" 2>/dev/null)
    if [ -n "$STARTED" ] && [ $(( $(date +%s) - STARTED )) -gt $((STALL_SECONDS * 2)) ] && [ ! -f "$SENTINEL.escalated" ]; then
      touch "$SENTINEL.escalated"
      log "ESCALATION: still stalled ${AGE}s after the automatic restart"
      notify "Everett ALARM: Wheeler is STILL stalled $((AGE / 60)) min after an automatic miner restart. The restart did not fix it. Check pc3080 (nvidia-smi, kawpowminer/wheeler.err) and build/wheeler.log."
    else
      log "still stalled: ${AGE}s at height $HEIGHT"
    fi
  fi
elif [ -f "$SENTINEL" ]; then
  rm -f "$SENTINEL" "$SENTINEL.escalated"
  log "RECOVERED: block $HEIGHT is ${AGE}s old"
  notify "Everett recovered: blocks are landing again (head $HEIGHT)."
else
  log "ok: height $HEIGHT, ${AGE}s old"
fi
