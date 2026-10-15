#!/bin/bash
set -euo pipefail
"dist/Master Reminder.app/Contents/MacOS/MasterReminder" --smoke-test > dist/runtime-smoke.log 2>&1 &
APP_PID=$!
for attempt in $(seq 1 60); do
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
assert results and all(results.values()), 'A runtime smoke check failed'
shutil.copy(source, 'dist/smoke-results.json')
for preview in source.parent.glob('*.png'):
    shutil.copy(preview, pathlib.Path('dist') / preview.name)
PY
