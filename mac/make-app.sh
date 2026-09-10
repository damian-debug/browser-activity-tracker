#!/bin/bash
# Assembles TimeTracker.app from the SPM build.
#
# We build the bundle by hand rather than using an .xcodeproj so the whole
# thing stays scriptable and reviewable as plain text. Xcode can still open
# TimeTrackerApp/Package.swift directly for debugging.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP_NAME="Activity Tracker"
BUNDLE_ID="studio.goodspeed.timetracker"
VERSION="${VERSION:-0.1.0}"
APP="build/${APP_NAME}.app"

# Release builds go to other people's Macs, so they are universal. An
# arm64-only binary does not launch on an Intel Mac and the failure is opaque
# ("the application cannot be opened"), so this is not worth leaving to chance.
# Debug builds stay single-arch to keep the edit/run loop fast.
echo "==> Building ($CONFIG)"
if [ "$CONFIG" = "release" ]; then
    # Universal builds land under a different path than single-arch ones.
    BUILD_DIR="TimeTrackerApp/.build/apple/Products/Release"
    (cd TimeTrackerApp && swift build -c release --arch arm64 --arch x86_64)
else
    BUILD_DIR="TimeTrackerApp/.build/${CONFIG}"
    (cd TimeTrackerApp && swift build -c "$CONFIG")
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/TimeTrackerApp" "$APP/Contents/MacOS/TimeTrackerApp"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>TimeTrackerApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>

    <!-- Tells scripts/uninstall.sh this build understands
         --unregister-login-item. A build without it would ignore the flag
         and simply launch, so the uninstaller must not pass it blindly. -->
    <key>ActivityTrackerUninstallHook</key><true/>

    <!-- Agent app: no Dock icon, no app menu. The menu bar item is the app. -->
    <key>LSUIElement</key><true/>

    <!-- Declared ahead of the phases that need them. Without the Apple Events
         string, macOS refuses the event with no prompt at all (-1743). -->
    <key>NSAccessibilityUsageDescription</key>
    <string>Activity Tracker reads the title and document of the window you are working in, so time can be attributed to the right project. This never leaves your Mac.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Activity Tracker asks your browser for the address of the page you are viewing, so time on a site can be attributed to the right project. This never leaves your Mac.</string>
</dict>
</plist>
PLIST

# Signing identity.
#
# TCC keys the Accessibility grant to the code signature. Ad-hoc signing
# produces a new signature on every build, so macOS silently drops the grant
# and AXIsProcessTrusted() starts returning false while System Settings still
# shows the app as allowed — the classic, maddening version of this bug.
#
# A stable self-signed identity avoids it. Create one once (see mac/README.md);
# until then we fall back to ad-hoc, which works but means re-granting
# Accessibility after each rebuild.
IDENTITY="TimeTracker Local Signing"

# Only use the identity if it can actually sign. An identity can exist, and
# even be trusted, yet still be refused by codesign for a subtly wrong key
# usage — so probe it rather than trusting that it is there.
sign_with_identity() {
    codesign --force --deep --options runtime \
        --entitlements TimeTrackerApp/TimeTracker.entitlements \
        --sign "$IDENTITY" "$APP" 2>/dev/null
}

if sign_with_identity; then
    echo "==> Signed with '$IDENTITY' (stable — permissions survive rebuilds)"
elif [ "$CONFIG" = "release" ]; then
    # Ad-hoc is tolerable locally but never for a release. Its designated
    # requirement is derived from the code hash, so it changes with every
    # build — every teammate would silently lose Accessibility on every
    # update, with System Settings still showing the app as allowed.
    echo "ERROR: cannot sign a release without '$IDENTITY'." >&2
    echo "       Run ./scripts/create-signing-identity.sh first." >&2
    exit 1
else
    echo "==> Signing ad-hoc (no usable '$IDENTITY')"
    echo "    Accessibility will need re-granting after each rebuild."
    echo "    Run ./scripts/create-signing-identity.sh to fix that permanently."
    codesign --force --deep --sign - "$APP" 2>/dev/null
fi

echo "==> Built $APP"
