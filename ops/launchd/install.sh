#!/usr/bin/env bash
# Install the Everett bootnode-host services as launchd user agents.
# Idempotent: re-running updates plists and restarts the agents.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
AGENTS=~/Library/LaunchAgents
mkdir -p "$AGENTS"
for p in "$HERE"/com.everett.*.plist; do
  name=$(basename "$p")
  sed "s|__HOME__|$HOME|g" "$p" > "$AGENTS/$name"
  launchctl unload "$AGENTS/$name" 2>/dev/null || true
  launchctl load "$AGENTS/$name"
  echo "loaded $name"
done
launchctl list | grep com.everett
