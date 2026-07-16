#!/bin/bash
set -e

# Rebuilds the helper from source and copies the result into prebuilt/, which is
# committed so that machines without Xcode or a signing certificate can install a
# working, properly signed helper.
#
# Run this after any change to FantasticalHelper.swift, Info.plist, or the
# entitlements. Nothing runs it automatically: build.sh writes to dist/ on every
# build, and refreshing a committed artifact on each dev build would turn every
# unrelated commit into a binary diff.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILT_APP="$ROOT_DIR/dist/native/FantasticalHelper.app"
PREBUILT_DIR="$ROOT_DIR/prebuilt"

# Without an identity, build.sh would install the existing prebuilt and we would
# copy it straight back over itself: a no-op that looks like a refresh.
if [ -z "${MCP_FANTASTICAL_SIGN_IDENTITY:-}" ]; then
    echo "ERROR: MCP_FANTASTICAL_SIGN_IDENTITY is not set." >&2
    echo "       The prebuilt bundle must be built from source with a real" >&2
    echo "       certificate, or its designated requirement cannot be pinned." >&2
    echo "       List candidates with: security find-identity -v -p codesigning" >&2
    exit 1
fi

"$SCRIPT_DIR/build.sh"

mkdir -p "$PREBUILT_DIR"
rm -rf "$PREBUILT_DIR/FantasticalHelper.app"
ditto "$BUILT_APP" "$PREBUILT_DIR/FantasticalHelper.app"

echo
echo "Refreshed: $PREBUILT_DIR/FantasticalHelper.app"
echo "Commit it so other machines get the update."
