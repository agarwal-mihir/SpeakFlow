#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SpeakFlow"
VERSION="${VERSION:-1.0.0}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Desktop}"
OUTPUT_DMG="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"
APP_BUNDLE="${APP_BUNDLE:-}"

if [[ -z "$APP_BUNDLE" ]]; then
  if [[ -d "/Applications/$APP_NAME.app" ]]; then
    APP_BUNDLE="/Applications/$APP_NAME.app"
  elif [[ -d "$WORKDIR/dist-swift/$APP_NAME.app" ]]; then
    APP_BUNDLE="$WORKDIR/dist-swift/$APP_NAME.app"
  fi
fi

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found. Build app first or pass APP_BUNDLE=/path/to/SpeakFlow.app" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "/tmp/${APP_NAME}.swift.dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

mkdir -p "$OUTPUT_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$OUTPUT_DMG"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

echo "Created DMG: $OUTPUT_DMG"
