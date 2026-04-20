#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$ROOT_DIR/dist/native"
APP_BUNDLE="$DIST_DIR/FantasticalHelper.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

echo "Building FantasticalHelper.app..."

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"

swiftc -O -o "$MACOS_DIR/fantastical-helper" \
    "$SCRIPT_DIR/FantasticalHelper.swift" \
    -framework EventKit \
    -framework Foundation

cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc sign so macOS TCC has a stable code identity to attribute the
# calendar permission to. Without this, permission never inherits through
# Claude Desktop -> npx -> node -> helper, and macOS never prompts.
codesign --force --sign - "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
