#!/bin/bash
set -euo pipefail

export COPYFILE_DISABLE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="MacRecorder"
APP_ID="com.macrecorder.app"
APP_VERSION="0.2.0"

BUILD_ROOT="$REPO_ROOT/dist/installer-work"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
PKG_ROOT="$BUILD_ROOT/pkgroot"
PKG_SCRIPTS="$BUILD_ROOT/pkg-scripts"
OUTPUT_PKG="$REPO_ROOT/dist/${APP_NAME}-${APP_VERSION}.pkg"

ENGINE_SOURCE="$REPO_ROOT/engine"
SWIFT_DIR="$REPO_ROOT/MacRecorder"
SWIFT_EXECUTABLE="$SWIFT_DIR/.build/release/MacRecorder"

echo "[installer] Cleaning previous artifacts"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$PKG_ROOT/Applications" "$PKG_SCRIPTS" "$REPO_ROOT/dist"

echo "[installer] Building Swift app (release)"
(cd "$SWIFT_DIR" && swift build -c release)

if [[ ! -x "$SWIFT_EXECUTABLE" ]]; then
  echo "[installer] Missing executable: $SWIFT_EXECUTABLE" >&2
  exit 1
fi

echo "[installer] Assembling app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$SWIFT_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SWIFT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

mkdir -p "$APP_BUNDLE/Contents/Resources/engine-template"
rsync -a \
  --exclude ".venv" \
  --exclude "__pycache__" \
  --exclude ".pytest_cache" \
  --exclude ".ruff_cache" \
  --exclude ".DS_Store" \
  --exclude "._*" \
  --exclude "*.pyc" \
  --exclude "tests" \
  "$ENGINE_SOURCE/" "$APP_BUNDLE/Contents/Resources/engine-template/"

cp "$REPO_ROOT/scripts/bootstrap_engine.sh" "$APP_BUNDLE/Contents/Resources/bootstrap_engine.sh"
chmod +x "$APP_BUNDLE/Contents/Resources/bootstrap_engine.sh"
xattr -cr "$APP_BUNDLE" || true

echo "[installer] Preparing pkg payload"
ditto --norsrc --noextattr "$APP_BUNDLE" "$PKG_ROOT/Applications/$APP_NAME.app"
cp "$REPO_ROOT/scripts/postinstall" "$PKG_SCRIPTS/postinstall"
chmod +x "$PKG_SCRIPTS/postinstall"
xattr -cr "$PKG_ROOT" || true

echo "[installer] Building pkg"
pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --filter '/\._' \
  --filter '\.DS_Store$' \
  --filter '/\.git($|/)' \
  --identifier "$APP_ID" \
  --version "$APP_VERSION" \
  "$OUTPUT_PKG"

echo "[installer] Created: $OUTPUT_PKG"
