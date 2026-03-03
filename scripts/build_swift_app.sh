#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$WORKDIR/swift/SpeakFlow"
APP_NAME="SpeakFlow"
PROJECT_FILE="$PKG_DIR/SpeakFlow.xcodeproj"
APP_BUNDLE="$WORKDIR/dist-swift/$APP_NAME.app"
APP_INSTALL_DIR="${APP_INSTALL_DIR:-/Applications}"
INSTALL_APP="$APP_INSTALL_DIR/$APP_NAME.app"
BUILD_CONFIG="${BUILD_CONFIG:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PKG_DIR/.deriveddata}"

if [[ ! -d "$PKG_DIR" ]]; then
  echo "Swift project not found at $PKG_DIR" >&2
  exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$WORKDIR/dist-swift"

if [[ ! -d "$PROJECT_FILE" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    (cd "$PKG_DIR" && xcodegen generate)
  else
    echo "Missing $PROJECT_FILE and xcodegen is not installed." >&2
    echo "Install xcodegen (`brew install xcodegen`) or add the project file." >&2
    exit 1
  fi
fi

xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$APP_NAME" \
  -configuration "$BUILD_CONFIG" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIG/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build failed: missing app bundle $BUILT_APP" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
cp -R "$BUILT_APP" "$APP_BUNDLE"

if [[ -d "$APP_INSTALL_DIR" && -w "$APP_INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_APP"
  cp -R "$APP_BUNDLE" "$INSTALL_APP"
  echo "Installed: $INSTALL_APP"
else
  echo "Built app bundle: $APP_BUNDLE"
  echo "No write access to $APP_INSTALL_DIR. Install manually:" >&2
  echo "  sudo rm -rf '$INSTALL_APP' && sudo cp -R '$APP_BUNDLE' '$INSTALL_APP'" >&2
fi
