#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/App"
BUILD_DIR="$ROOT_DIR/build"
BUNDLE="$BUILD_DIR/CalmPage Native.app"

cd "$APP_DIR"
swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$APP_DIR/.build/release/CalmPageNative" "$BUNDLE/Contents/MacOS/CalmPageNative"
cp "$APP_DIR/Packaging/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$APP_DIR/Packaging/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
chmod +x "$BUNDLE/Contents/MacOS/CalmPageNative"

echo "$BUNDLE"
