#!/usr/bin/env bash
# Rotate the launchd service logs under build/. launchd never truncates
# StandardOutPath/StandardErrorPath files, so they grow without bound
# (wheeler.log alone runs ~60MB/day) and would eventually fill the disk
# under the live node.
#
# Copytruncate style so the running services never need a reload: for any
# log over MAX_BYTES, keep the last KEEP_BYTES in <log>.1, then truncate
# the live file in place with ': >'. This is safe because launchd opens
# these logs in append mode (O_APPEND), so after truncation the writers
# keep appending at the new end of file. A few lines written between the
# tail copy and the truncate can be lost; acceptable for service logs.
#
# Installed as com.everett.logrotate (StartCalendarInterval, daily) by
# ops/launchd/install.sh. Runs once and exits; launchd rescheduled.
set -u
LOGDIR="${LOGDIR:-$HOME/everett/build}"
MAX_BYTES=$((50 * 1024 * 1024))   # rotate when a log exceeds 50MB
KEEP_BYTES=$((10 * 1024 * 1024))  # tail kept in the .1 file

for f in "$LOGDIR"/*.log; do
  [ -f "$f" ] || continue
  size=$(stat -f %z "$f" 2>/dev/null) || continue
  [ "$size" -gt "$MAX_BYTES" ] || continue
  if tail -c "$KEEP_BYTES" "$f" > "$f.1"; then
    : > "$f"
    echo "$(date '+%Y-%m-%d %H:%M:%S') rotated $f ($size bytes; kept last $KEEP_BYTES in $f.1)"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') FAIL: could not copy tail of $f; left untruncated" >&2
  fi
done
