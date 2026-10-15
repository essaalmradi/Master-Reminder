#!/bin/bash
set -euo pipefail
# Intentionally no set -x: neither secret nor keychain password enters logs.
: "${RUNNER_TEMP:?Run signing only in the CI runner}"
: "${MACOS_CERTIFICATE_P12:?Missing MACOS_CERTIFICATE_P12 secret}"
: "${MACOS_CERTIFICATE_PASSWORD:?Missing MACOS_CERTIFICATE_PASSWORD secret}"
KEYCHAIN_PATH="$RUNNER_TEMP/master-reminder-signing.keychain-db"
CERT_PATH="$RUNNER_TEMP/master-reminder-certificate.p12"
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
export CERT_PATH
cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  rm -f "$CERT_PATH"
}
trap cleanup EXIT
python3 - <<'PY'
import base64, os
with open(os.environ['CERT_PATH'], 'wb') as f:
    f.write(base64.b64decode(os.environ['MACOS_CERTIFICATE_P12']))
os.chmod(os.environ['CERT_PATH'], 0o600)
PY
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | sed -n 's/.*"\(Developer ID Application:.*(KTA6FSZK9V)\)".*/\1/p' | head -n 1)"
if [ -z "$IDENTITY" ]; then
  echo '::error::No valid Developer ID Application identity for team KTA6FSZK9V in the supplied P12.'
  exit 1
fi
APP="dist/Master Reminder.app"
codesign --force --options runtime --timestamp --keychain "$KEYCHAIN_PATH" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2> dist/codesign.txt
cat dist/codesign.txt
grep -q '^TeamIdentifier=KTA6FSZK9V$' dist/codesign.txt
grep -q '^Authority=Developer ID Application:' dist/codesign.txt
# No notarization in this personal-use build. The timestamp does not notarize or publish it.
