#!/usr/bin/env bash
# Keep the bootnode's NAT-PMP port mappings alive (they expire hourly).
# Run in the background on the bootnode host: nohup scripts/nat_renew.sh &
# Requires: brew install libnatpmp
set -u
while true; do
  natpmpc -a 30303 30303 tcp 3600 >/dev/null 2>&1
  natpmpc -a 30303 30303 udp 3600 >/dev/null 2>&1
  sleep 1740
done
