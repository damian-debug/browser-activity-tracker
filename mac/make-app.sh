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
VERSION="0.1.0"
BUILD_DIR="TimeTrackerApp/.build/${CONFIG}"
APP="build/${APP_NAME}.app"

echo "==> Building ($CONFIG)"
(cd TimeTrackerApp && swift build -c "$CONFIG")

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

# Ad-hoc signing is enough while the app requests no permissions. Before
# Phase 2 this must become a stable self-signed identity: TCC keys the
# Accessibility grant to the signature, so a signature that changes on every
# rebuild silently revokes it.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "==> Built $APP"
