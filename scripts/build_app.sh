#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$WORKDIR/.venv"
DIST_APP="$WORKDIR/dist/SpeakFlow.app"
APP_INSTALL_DIR="${APP_INSTALL_DIR:-/Applications}"
INSTALL_APP="$APP_INSTALL_DIR/SpeakFlow.app"
SPEC_FILE="$WORKDIR/SpeakFlow.spec"

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "Missing virtualenv at $VENV. Create it first with: python3 -m venv .venv" >&2
  exit 1
fi

source "$VENV/bin/activate"

python -m pip install -U pip setuptools wheel
python -m pip install -e '.[app]'

rm -rf "$WORKDIR/build" "$WORKDIR/dist"

pyinstaller --noconfirm --clean "$SPEC_FILE"

if [[ ! -d "$DIST_APP" ]]; then
  echo "Build failed. App not found at $DIST_APP" >&2
  exit 1
fi

if [[ ! -d "$APP_INSTALL_DIR" ]]; then
  echo "Install directory does not exist: $APP_INSTALL_DIR" >&2
  exit 1
fi

if [[ ! -w "$APP_INSTALL_DIR" ]]; then
  echo "No write permission for: $APP_INSTALL_DIR" >&2
  echo "Copy the built app manually:" >&2
  echo "  sudo rm -rf '$INSTALL_APP' && sudo cp -R '$DIST_APP' '$INSTALL_APP'" >&2
  echo "Or install to user Applications with:" >&2
  echo "  APP_INSTALL_DIR='$HOME/Applications' bash scripts/build_app.sh" >&2
  exit 1
fi

rm -rf "$INSTALL_APP"
cp -R "$DIST_APP" "$INSTALL_APP"

echo "Installed app bundle at: $INSTALL_APP"
echo "Launch it with: open '$INSTALL_APP'"
