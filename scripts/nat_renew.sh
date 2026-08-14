#!/usr/bin/env bash
# Keep the bootnode's NAT-PMP port mappings alive (they expire hourly).
# Runs under launchd as com.everett.natpmp: long-lived loop, one renewal
# round every 29 minutes against the 3600s leases.
# Requires: brew install libnatpmp
#
# Every attempt is logged with a timestamp to build/natpmp.log. After 3
# consecutive failed rounds the sentinel build/natpmp.FAILING is written
# (and removed on the next success) so the operator or dashboard can see
# that port 30303 may no longer be reachable from outside.
set -u
EVERETT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$EVERETT/build/natpmp.log"
SENTINEL="$EVERETT/build/natpmp.FAILING"
mkdir -p "$EVERETT/build"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

fails=0
while true; do
  ok=1
  if ! command -v natpmpc >/dev/null 2>&1; then
    ok=0
    log "FAIL: natpmpc not found in PATH ($PATH); install with: brew install libnatpmp"
  else
    for proto in tcp udp; do
      out=$(natpmpc -a 30303 30303 "$proto" 3600 2>&1); rc=$?
      if [ "$rc" -eq 0 ]; then
        log "renewed $proto 30303 (3600s lease)"
      else
        ok=0
        log "FAIL: natpmpc $proto renewal rc=$rc: $(echo "$out" | tail -1)"
      fi
    done
  fi
  if [ "$ok" -eq 1 ]; then
    if [ "$fails" -gt 0 ] || [ -e "$SENTINEL" ]; then
      log "recovered after $fails failed round(s)"
    fi
    fails=0
    rm -f "$SENTINEL"
  else
    fails=$((fails + 1))
    log "consecutive failed rounds: $fails"
    if [ "$fails" -ge 3 ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') NAT-PMP renewal failing ($fails consecutive rounds); bootnode port 30303 may be unreachable externally. See build/natpmp.log" > "$SENTINEL"
      log "ALERT: sentinel $SENTINEL written"
    fi
  fi
  sleep 1740
done
