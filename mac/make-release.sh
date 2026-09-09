#!/bin/bash
# Packages a signed, universal Activity Tracker.app for distribution to the team.
#
# The output is a plain zip published as a GitHub release asset, installed by
# scripts/install.sh. There is deliberately no Apple Developer ID and no
# notarization: see INSTALL.md for why that is workable here, and what it costs.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "usage: ./make-release.sh <version>   e.g. ./make-release.sh 0.2.0" >&2
    exit 1
fi

APP="build/Activity Tracker.app"
DIST="dist"
ZIP="${DIST}/ActivityTracker.zip"

# The team's Accessibility grants are pinned to this exact leaf certificate.
# Every release must be signed with it or everyone re-grants permission by
# hand, so the build asserts it rather than trusting that it happened.
EXPECTED_CERT_SHA1="3f945c138150ced62d00c0ce0555cab797fa5acb"

echo "==> Building release $VERSION"
VERSION="$VERSION" ./make-app.sh release

echo "==> Verifying architectures"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/TimeTrackerApp")
echo "    $ARCHS"
case "$ARCHS" in
    *x86_64*arm64*|*arm64*x86_64*) ;;
    *) echo "ERROR: not universal — Intel Macs could not run this." >&2; exit 1 ;;
esac

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"
DR=$(codesign -d -r- "$APP" 2>&1 | grep '^designated')
echo "    $DR"
case "$DR" in
    *"$EXPECTED_CERT_SHA1"*) ;;
    *)
        echo "ERROR: signed with an unexpected certificate." >&2
        echo "       Every teammate would have to re-grant Accessibility." >&2
        exit 1
        ;;
esac

# install.sh carries the same hash so it can reject a tampered download. If the
# signing identity is ever rotated, both sides must move together.
if ! grep -q "$EXPECTED_CERT_SHA1" scripts/install.sh; then
    echo "ERROR: scripts/install.sh pins a different certificate hash." >&2
    exit 1
fi

echo "==> Packaging"
rm -rf "$DIST"
mkdir -p "$DIST"
# ditto, not zip: it preserves the signature, symlinks and resource forks that
# a plain `zip` quietly mangles, which shows up later as a broken signature.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Verifying the packaged copy"
VERIFY_DIR=$(mktemp -d)
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Activity Tracker.app"
echo "    signature survived packaging"

shasum -a 256 "$ZIP" | awk '{print $1}' > "${ZIP}.sha256"

echo
echo "==> Built $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "    sha256 $(cat "${ZIP}.sha256")"
echo
echo "Publish it with:"
echo "  gh release create v${VERSION} \"${ZIP}\" --title \"Activity Tracker ${VERSION}\" --notes \"...\""
echo
echo "Team install command (unchanged between releases):"
echo "  curl -fsSL https://raw.githubusercontent.com/damian-debug/browser-activity-tracker/master/mac/scripts/install.sh | bash"
