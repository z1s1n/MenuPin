#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${MENUPIN_BUILD_DIR:-$ROOT/.build}"
CACHE="${MENUPIN_CACHE_DIR:-$BUILD/cache}"
mkdir -p "$CACHE" "$BUILD"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
export SWIFT_MODULECACHE_PATH="$CACHE/swift"
swift run --disable-sandbox --package-path "$ROOT" --scratch-path "$BUILD" --cache-path "$CACHE/spm" --config-path "$CACHE/config" --security-path "$CACHE/security" MenuPinTests
