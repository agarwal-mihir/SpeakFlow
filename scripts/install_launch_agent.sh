#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
PY_TEMPLATE="$WORKDIR/launchd/com.speakflow.desktop.plist.template"
APP_TEMPLATE="$WORKDIR/launchd/com.speakflow.desktop.app.plist.template"
DEST="$HOME/Library/LaunchAgents/com.speakflow.desktop.plist"
LOG_DIR="$HOME/Library/Logs/SpeakFlow"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
APP_BIN="${APP_BIN:-}"
APP_BUNDLE="${APP_BUNDLE:-}"

if [[ -z "$APP_BUNDLE" ]]; then
  if [[ -d "/Applications/SpeakFlow.app" ]]; then
    APP_BUNDLE="/Applications/SpeakFlow.app"
  elif [[ -d "$HOME/Applications/SpeakFlow.app" ]]; then
    APP_BUNDLE="$HOME/Applications/SpeakFlow.app"
  elif [[ -d "$WORKDIR/dist/SpeakFlow.app" ]]; then
    APP_BUNDLE="$WORKDIR/dist/SpeakFlow.app"
  fi
fi

if [[ ! -f "$PY_TEMPLATE" ]]; then
  echo "Template not found: $PY_TEMPLATE" >&2
  exit 1
fi

if [[ ! -f "$APP_TEMPLATE" ]]; then
  echo "Template not found: $APP_TEMPLATE" >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$LOG_DIR"

if [[ -n "$APP_BUNDLE" ]]; then
  if [[ -z "$APP_BIN" ]]; then
    APP_BIN="$APP_BUNDLE/Contents/MacOS/SpeakFlow"
  fi
  if [[ ! -x "$APP_BIN" ]]; then
    echo "App executable not found: $APP_BIN" >&2
    echo "Set APP_BIN manually if your executable name is different." >&2
    exit 1
  fi
  sed \
    -e "s|{{APP_BUNDLE}}|$APP_BUNDLE|g" \
    -e "s|{{APP_BIN}}|$APP_BIN|g" \
    -e "s|{{LOG_DIR}}|$LOG_DIR|g" \
    "$APP_TEMPLATE" > "$DEST"
  echo "Using app bundle for launch agent: $APP_BUNDLE"
  echo "Using app executable for launch agent: $APP_BIN"
else
  sed \
    -e "s|{{WORKDIR}}|$WORKDIR|g" \
    -e "s|{{PYTHON_BIN}}|$PYTHON_BIN|g" \
    -e "s|{{LOG_DIR}}|$LOG_DIR|g" \
    "$PY_TEMPLATE" > "$DEST"
  echo "Using python module mode for launch agent: $PYTHON_BIN"
fi

launchctl bootout "gui/$UID/com.speakflow.desktop" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$DEST"
launchctl enable "gui/$UID/com.speakflow.desktop"
launchctl kickstart -k "gui/$UID/com.speakflow.desktop"

echo "Installed launch agent: $DEST"
