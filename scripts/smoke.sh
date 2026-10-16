#!/bin/bash
set -euo pipefail
APP="${1:-$PWD/dist/Master Reminder.app}"
"$APP/Contents/MacOS/MasterReminder" --smoke-test > dist/runtime-smoke.log 2>&1 &
APP_PID=$!
for attempt in $(seq 1 120); do
  if ! kill -0 "$APP_PID" 2>/dev/null; then break; fi
  sleep 1
done
if kill -0 "$APP_PID" 2>/dev/null; then
  sample "$APP_PID" 1 -file dist/hang-sample.txt || true
  kill "$APP_PID"
  echo '::error::Runtime smoke timed out'
  exit 1
fi
wait "$APP_PID"
python3 - <<'PY'
import json, os, pathlib, shutil, tempfile
source = pathlib.Path(tempfile.gettempdir()) / 'MasterReminder-Smoke' / 'smoke-results.json'
results = json.loads(source.read_text())
print(json.dumps(results, indent=2))
shutil.copy(source, 'dist/smoke-results.json')
for preview in source.parent.glob('*.png'):
    shutil.copy(preview, pathlib.Path('dist') / preview.name)
assert results and all(results.values()), 'A runtime smoke check failed'
PY

# Reproduce the reported launch failure with an existing, completed profile.
# Unlike --smoke-test, --launch-check cannot force a window open.
LAUNCH_REPORT="$(python3 -c 'import pathlib,tempfile; print(pathlib.Path(tempfile.gettempdir()) / "MasterReminder-Smoke" / "launch-check.json")')"
rm -f "$LAUNCH_REPORT"
open -n "$APP" --args --launch-check
for attempt in $(seq 1 20); do
  if [ -f "$LAUNCH_REPORT" ]; then break; fi
  sleep 1
done
python3 - "$LAUNCH_REPORT" <<'PY'
import json, pathlib, shutil, sys
source = pathlib.Path(sys.argv[1])
assert source.exists(), 'App did not report after Launch Services launch'
results = json.loads(source.read_text())
print(json.dumps(results, indent=2))
assert results and all(results.values()), 'Existing-user launch regression'
shutil.copy(source, 'dist/launch-check.json')
PY
