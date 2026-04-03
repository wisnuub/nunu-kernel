#!/usr/bin/env bash
# build.sh — builds and signs nunu-vm
#
# Usage:
#   ./build.sh                   # debug build, ad-hoc signed (local dev)
#   ./build.sh --release         # release build, ad-hoc signed
#   ./build.sh --release --sign  # release build, Developer ID signed (CI/dist)
#
# For --sign, set these env vars (GitHub Actions secrets):
#   APPLE_SIGNING_IDENTITY  — e.g. "Developer ID Application: Name (TEAMID)"
#   APPLE_TEAM_ID           — your 10-char Apple team ID
#
# Notarization (run after --sign):
#   xcrun notarytool submit nunu-vm.zip \
#     --apple-id "$APPLE_ID" \
#     --password "$APPLE_APP_PASSWORD" \
#     --team-id  "$APPLE_TEAM_ID" \
#     --wait

set -euo pipefail

RELEASE=false
SIGN=false

for arg in "$@"; do
    case $arg in
        --release) RELEASE=true ;;
        --sign)    SIGN=true    ;;
    esac
done

# ── Build ─────────────────────────────────────────────────────────────────────

CONFIG="debug"
if [ "$RELEASE" = true ]; then
    CONFIG="release"
    echo "Building release..."
    swift build -c release
else
    echo "Building debug..."
    swift build
fi

BINARY=".build/$CONFIG/NunuVM"

if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found at $BINARY" >&2
    exit 1
fi

# ── Sign ──────────────────────────────────────────────────────────────────────

ENTITLEMENTS="$(dirname "$0")/NunuVM.entitlements"

if [ "$SIGN" = true ]; then
    # Developer ID — for distribution inside nunu.app
    IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
    if [ -z "$IDENTITY" ]; then
        echo "Error: APPLE_SIGNING_IDENTITY not set" >&2
        exit 1
    fi
    echo "Signing with Developer ID: $IDENTITY"
    codesign \
        --sign "$IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        --options runtime \
        --timestamp \
        --force \
        "$BINARY"
else
    # Ad-hoc — works locally without an Apple Developer account
    echo "Signing ad-hoc (local dev)..."
    codesign \
        --sign - \
        --entitlements "$ENTITLEMENTS" \
        --force \
        "$BINARY"
fi

# ── Verify ────────────────────────────────────────────────────────────────────

echo "Verifying signature..."
codesign --verify --verbose "$BINARY"

echo ""
echo "Checking entitlements..."
codesign -d --entitlements - "$BINARY" 2>/dev/null | \
    grep -E "virtualization|network" || true

echo ""
echo "Done: $BINARY"
