#!/bin/bash
set -euo pipefail
PROJECT="$PWD"
CHECK_ROOT="$(mktemp -d "$RUNNER_TEMP/master-reminder-install.XXXXXX")"
MOUNT="$CHECK_ROOT/mount"
mkdir -p "$MOUNT" "$CHECK_ROOT/current" "$CHECK_ROOT/previous"
cleanup() {
  hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  if [ -d "$CHECK_ROOT/build-hidden" ]; then mv "$CHECK_ROOT/build-hidden" "$PROJECT/.build"; fi
}
trap cleanup EXIT

# Use the actual delivered disk image, then install the signed .app outside the checkout.
hdiutil attach "$PROJECT/dist/Master-Reminder-0.4.0.dmg" -readonly -nobrowse -mountpoint "$MOUNT"
ditto "$MOUNT/Master Reminder.app" "$CHECK_ROOT/current/Master Reminder.app"
hdiutil detach "$MOUNT"
codesign --verify --deep --strict --verbose=2 "$CHECK_ROOT/current/Master Reminder.app"

# Keep a comparative result while the known-broken 0.2.1 CI artifact is retained.
# Artifact expiry may skip this historical comparison, never the installed-app gate.
BASELINE_AVAILABLE=0
if gh run download 38829000780 --repo "$GITHUB_REPOSITORY" --name Master-Reminder-0.2.1-macOS-arm64 --dir "$CHECK_ROOT/baseline"; then
  hdiutil attach "$CHECK_ROOT/baseline/Master-Reminder-0.2.1.dmg" -readonly -nobrowse -mountpoint "$MOUNT"
  ditto "$MOUNT/Master Reminder.app" "$CHECK_ROOT/previous/Master Reminder.app"
  hdiutil detach "$MOUNT"
  BASELINE_AVAILABLE=1
fi

# The absolute path embedded by SwiftPM must not exist during either launch.
mv "$PROJECT/.build" "$CHECK_ROOT/build-hidden"
test ! -e "$PROJECT/.build"
python3 - "$CHECK_ROOT" "$BASELINE_AVAILABLE" "$PROJECT/dist" <<'PY'
import json, pathlib, subprocess, sys
root, available, dist = pathlib.Path(sys.argv[1]), sys.argv[2] == '1', pathlib.Path(sys.argv[3])
result = {'buildDirectoryUnavailable': True, 'previousVersionCompared': available}
if available:
    previous = root / 'previous/Master Reminder.app/Contents/MacOS/MasterReminder'
    run = subprocess.run([str(previous), '--launch-check'], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)
    (dist / 'previous-version-crash.log').write_text(run.stdout)
    message = run.stdout.lower()
    result.update(previousExitCode=run.returncode,
                  previousResourceCrash=run.returncode != 0 and ('unable to find bundle' in message or 'could not load resource bundle' in message))
    assert result['previousResourceCrash'], 'Historical app did not reproduce the expected missing-resource crash; inspect its log'
(dist / 'installed-validation.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
PY
bash "$PROJECT/scripts/smoke.sh" "$CHECK_ROOT/current/Master Reminder.app"
python3 - "$PROJECT/dist" <<'PY'
import json, pathlib, sys
dist = pathlib.Path(sys.argv[1])
result = json.loads((dist / 'installed-validation.json').read_text())
smoke = json.loads((dist / 'smoke-results.json').read_text())
launch = json.loads((dist / 'launch-check.json').read_text())
assert smoke['resourcesInsideInstalledApp'] and all(smoke.values()) and all(launch.values())
result.update(currentInstalledAppPassed=True, currentResourcesInsideApp=True, currentRelaunchPassed=True)
(dist / 'installed-validation.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
PY
