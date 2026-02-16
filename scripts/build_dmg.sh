#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SpeakFlow"
DIST_DIR="$WORKDIR/dist"
VERSION="$(awk -F'\"' '/^version = / {print $2; exit}' "$WORKDIR/pyproject.toml")"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Desktop}"
OUTPUT_DMG="$OUTPUT_DIR/$DMG_NAME"
VOL_NAME="$APP_NAME"
APP_BUNDLE="${APP_BUNDLE:-}"

if [[ -z "$APP_BUNDLE" ]]; then
  if [[ -d "/Applications/$APP_NAME.app" ]]; then
    APP_BUNDLE="/Applications/$APP_NAME.app"
  elif [[ -d "$HOME/Applications/$APP_NAME.app" ]]; then
    APP_BUNDLE="$HOME/Applications/$APP_NAME.app"
  elif [[ -d "$DIST_DIR/$APP_NAME.app" ]]; then
    APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
  fi
fi

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found." >&2
  echo "Provide it with APP_BUNDLE=... or place SpeakFlow.app in /Applications, ~/Applications, or dist/." >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "/tmp/${APP_NAME}.dmg.staging.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$OUTPUT_DMG"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

echo "Packaged app bundle: $APP_BUNDLE"
echo "Created DMG: $OUTPUT_DMG"
