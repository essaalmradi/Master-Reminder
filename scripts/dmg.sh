#!/bin/bash
set -euo pipefail
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "dist/Master Reminder.app" "$STAGE/Master Reminder.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Master Reminder" -srcfolder "$STAGE" -ov -format UDZO "dist/Master-Reminder-0.2.0.dmg"
hdiutil verify "dist/Master-Reminder-0.2.0.dmg"
shasum -a 256 "dist/Master-Reminder-0.2.0.dmg" > dist/SHA256SUMS.txt
