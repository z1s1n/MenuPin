#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${MENUPIN_BUILD_DIR:-$ROOT/.build}"
CACHE="${MENUPIN_CACHE_DIR:-$BUILD/cache}"
mkdir -p "$CACHE" "$BUILD"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
export SWIFT_MODULECACHE_PATH="$CACHE/swift"
swift build --disable-sandbox --package-path "$ROOT" --scratch-path "$BUILD" --cache-path "$CACHE/spm" --config-path "$CACHE/config" --security-path "$CACHE/security" --product MenuPin -c release
APP="${MENUPIN_APP_PATH:-$ROOT/../MenuPin.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/release/MenuPin" "$APP/Contents/MacOS/MenuPin"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/AppIcon.icns" ]; then cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - --identifier local.menupin.app "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
