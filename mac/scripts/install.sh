#!/bin/bash
# Installs (or updates) Activity Tracker.
#
#   curl -fsSL https://raw.githubusercontent.com/damian-debug/browser-activity-tracker/master/mac/scripts/install.sh | bash
#
# Why a Terminal command rather than a double-clickable installer: macOS applies
# the com.apple.quarantine flag to anything downloaded by a browser, Slack, Mail
# or AirDrop, and quarantined apps without an Apple Developer ID are blocked by
# Gatekeeper behind several layers of scary dialog. curl does not set that flag,
# so installing this way is both fewer steps and less alarming. The signature is
# still verified below — this skips Apple's notarization, not the integrity check.
set -euo pipefail

REPO="damian-debug/browser-activity-tracker"
ZIP_URL="https://github.com/${REPO}/releases/latest/download/ActivityTracker.zip"
APP_NAME="Activity Tracker.app"
BUNDLE_ID="studio.goodspeed.timetracker"

# Pinned leaf certificate of the build machine's signing identity. This is what
# makes an unnotarized download safe to run: a tampered or substituted build
# cannot match it. It is also what lets macOS keep your Accessibility grant
# across updates, since the grant is keyed to this exact signature.
EXPECTED_CERT_SHA1="3f945c138150ced62d00c0ce0555cab797fa5acb"

say() { printf '\033[1m==>\033[0m %s\n' "$1"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Activity Tracker is macOS only."

# /Applications is group-writable by admins on a normal Mac; fall back to the
# user's own folder rather than asking for a password.
if [ -w /Applications ]; then
    DEST="/Applications"
else
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    say "No write access to /Applications — installing to $DEST"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say "Downloading"
curl -fsSL "$ZIP_URL" -o "$TMP/app.zip" \
    || die "Download failed. Is there a published release yet?"

say "Unpacking"
# ditto rather than unzip: it preserves the code signature intact.
ditto -x -k "$TMP/app.zip" "$TMP/unpacked" || die "Could not unpack the download."
SRC="$TMP/unpacked/$APP_NAME"
[ -d "$SRC" ] || die "The download did not contain $APP_NAME."

say "Verifying signature"
codesign --verify --deep --strict "$SRC" 2>/dev/null \
    || die "The signature is not valid. Do not run this build; tell Damian."
codesign -d -r- "$SRC" 2>&1 | grep -q "$EXPECTED_CERT_SHA1" \
    || die "This build was signed by an unexpected certificate. Do not run it; tell Damian."
say "Signature verified"

# Belt and braces: if someone fetched the zip through a browser first, the
# unpacked copy inherits the quarantine flag and Gatekeeper would block it.
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true

if pgrep -x TimeTrackerApp >/dev/null 2>&1; then
    say "Quitting the running copy"
    # Safe to stop at any moment: the in-flight session is checkpointed to disk
    # and restored on next launch, so no tracked time is lost.
    pkill -x TimeTrackerApp || true
    for _ in $(seq 1 20); do
        pgrep -x TimeTrackerApp >/dev/null 2>&1 || break
        sleep 0.25
    done
fi

UPDATING=false
[ -d "$DEST/$APP_NAME" ] && UPDATING=true

say "Installing to $DEST"
rm -rf "$DEST/$APP_NAME"
ditto "$SRC" "$DEST/$APP_NAME"

VERSION=$(defaults read "$DEST/$APP_NAME/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")

say "Launching"
open "$DEST/$APP_NAME"

echo
if [ "$UPDATING" = true ]; then
    printf '\033[32mUpdated to %s.\033[0m Your tracked history and permissions are untouched.\n' "$VERSION"
else
    printf '\033[32mInstalled %s.\033[0m Look for the timer in your menu bar.\n' "$VERSION"
    cat <<'NOTE'

One thing left to do: the app will ask for Accessibility permission.
Without it, it can only see which app you are in — with it, it can also see
window titles and open files, which is what makes attribution to a project work.

  System Settings > Privacy & Security > Accessibility > enable Activity Tracker

Everything stays on this Mac. The app makes no network requests at all,
and nothing is shared with anyone unless you export it yourself.
NOTE
fi
