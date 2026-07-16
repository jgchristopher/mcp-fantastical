#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$ROOT_DIR/dist/native"
APP_BUNDLE="$DIST_DIR/FantasticalHelper.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
PREBUILT_APP="$ROOT_DIR/prebuilt/FantasticalHelper.app"

# macOS records the calendar grant against this bundle's designated requirement
# (DR), so the DR must stay identical across rebuilds or TCC silently denies access.
#
# Ad-hoc (-) has no leaf certificate, so the identity falls back to the code hash
# and every rebuild reads as a different app. Signing with a real certificate fixes
# that, but codesign's *default* DR for an Apple Development certificate pins
# leaf[subject.CN] -- the full certificate name, including its per-certificate
# identifier. That breaks the grant whenever the certificate is reissued.
#
# So pin leaf[subject.OU] (the team ID) instead. It is stable across certificate
# renewals, and it is what Developer ID certificates pin by default anyway.
#
# Set MCP_FANTASTICAL_SIGN_IDENTITY to a stable identity, e.g.
#   export MCP_FANTASTICAL_SIGN_IDENTITY="Apple Development: Jane Doe (XXXXXXXXXX)"
# List candidates with: security find-identity -v -p codesigning
SIGN_IDENTITY="${MCP_FANTASTICAL_SIGN_IDENTITY:-}"

# Hardened runtime (--options runtime, below) makes TCC require an explicit
# entitlement per protected resource. Without
# com.apple.security.personal-information.calendars, tccd denies the calendar
# request instantly: no prompt, and no decision recorded in the TCC database, which
# looks exactly like the user having clicked Deny. The Info.plist usage description
# is necessary but not sufficient.
#
# Keep that file free of XML comments. AMFI parses entitlements with a stricter
# reader than plutil and fails on them ("AMFIUnserializeXML: syntax error").
ENTITLEMENTS="$SCRIPT_DIR/FantasticalHelper.entitlements"

# A machine that is not developing the helper has no reason to compile it. The
# prebuilt bundle is already signed with the DR pinned to the team ID, and TCC
# grants against that DR, so a copy behaves identically to a local build without
# needing Xcode or a signing certificate here.
#
# This branch also replaces what used to be the ad-hoc fallback. Ad-hoc signing
# has no leaf certificate, so the identity is the code hash and every rebuild
# reads as a different app that silently loses its grant. Copying a properly
# signed bundle is strictly better than producing a broken one.
if [ -z "$SIGN_IDENTITY" ] && [ -d "$PREBUILT_APP" ]; then
    echo "Installing prebuilt FantasticalHelper.app (no signing identity set)..."
    rm -rf "$APP_BUNDLE"
    mkdir -p "$DIST_DIR"
    ditto "$PREBUILT_APP" "$APP_BUNDLE"

    # Fail here rather than at the first calendar call, where a bad copy would
    # surface as "access denied" and read as a permissions problem.
    if ! codesign --verify --strict "$APP_BUNDLE" 2>/dev/null; then
        echo "ERROR: prebuilt bundle failed signature verification." >&2
        echo "       Refresh it on a machine with a signing identity: npm run build:prebuilt" >&2
        exit 1
    fi

    # Guards against shipping a bundle built before the entitlement was added.
    # Without it TCC denies instantly, shows no prompt, and records nothing --
    # indistinguishable from the user clicking Deny.
    if ! codesign -d --entitlements - --xml "$APP_BUNDLE" 2>/dev/null \
        | grep -q "personal-information.calendars"; then
        echo "ERROR: prebuilt bundle is missing the calendars entitlement." >&2
        echo "       It cannot prompt for access. Refresh it: npm run build:prebuilt" >&2
        exit 1
    fi

    echo "Installed: $APP_BUNDLE"
    echo "Designated requirement:"
    codesign -d -r- "$APP_BUNDLE" 2>&1 | sed -n 's/^designated/  designated/p'
    exit 0
fi

echo "Building FantasticalHelper.app..."

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"

swiftc -O -o "$MACOS_DIR/fantastical-helper" \
    "$SCRIPT_DIR/FantasticalHelper.swift" \
    -framework EventKit \
    -framework Foundation

cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -z "$SIGN_IDENTITY" ]; then
    echo "WARNING: no signing identity and no prebuilt bundle, falling back to ad-hoc signing."
    echo "         Calendar access will break after each rebuild until it is re-granted."
    echo "         See the comment in native/build.sh to fix this permanently."
    codesign --force --sign - "$APP_BUNDLE"
else
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SCRIPT_DIR/Info.plist")"
    TEAM_ID="$(security find-certificate -c "$SIGN_IDENTITY" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU *= *\([A-Za-z0-9]*\).*/\1/p')"

    echo "Signing with: $SIGN_IDENTITY"
    if [ -z "$TEAM_ID" ]; then
        # Without a team ID we cannot build the DR, and codesign's default would
        # pin the certificate CN. Say so rather than silently shipping a fragile grant.
        echo "WARNING: could not read a team ID (OU) from that certificate."
        echo "         Falling back to codesign's default requirement, which pins the"
        echo "         certificate name: calendar access will break when it is reissued."
        codesign --force --timestamp --options runtime \
            --entitlements "$ENTITLEMENTS" \
            --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    else
        echo "Pinning designated requirement to team: $TEAM_ID ($BUNDLE_ID)"
        codesign --force --timestamp --options runtime \
            --entitlements "$ENTITLEMENTS" \
            -r="designated => identifier \"$BUNDLE_ID\" and anchor apple generic and certificate leaf[subject.OU] = \"$TEAM_ID\"" \
            --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    fi
fi

echo "Built: $APP_BUNDLE"
echo "Designated requirement:"
codesign -d -r- "$APP_BUNDLE" 2>&1 | sed -n 's/^designated/  designated/p'
