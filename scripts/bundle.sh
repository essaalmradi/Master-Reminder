#!/bin/bash
set -euo pipefail
APP="dist/Master Reminder.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
install -m 755 "$BIN_DIR/MasterReminder" "$APP/Contents/MacOS/MasterReminder"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp Sources/MasterReminder/Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
swift scripts/make-icon.swift dist/AppIcon.iconset
iconutil --convert icns dist/AppIcon.iconset --output "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist"
file "$APP/Contents/MacOS/MasterReminder"
lipo -verify_arch arm64 "$APP/Contents/MacOS/MasterReminder"
