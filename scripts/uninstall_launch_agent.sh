#!/usr/bin/env bash
set -euo pipefail

DEST="$HOME/Library/LaunchAgents/com.speakflow.desktop.plist"

launchctl bootout "gui/$UID/com.speakflow.desktop" >/dev/null 2>&1 || true
launchctl disable "gui/$UID/com.speakflow.desktop" >/dev/null 2>&1 || true

if [[ -f "$DEST" ]]; then
  rm "$DEST"
fi

echo "Removed launch agent: $DEST"
