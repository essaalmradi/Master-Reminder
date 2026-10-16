#!/usr/bin/env python3
"""Check the built plists, not just the YAML or archive filename."""
import json, os, pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
rows = []
for bundle in [app, *app.glob('PlugIns/*.appex')]:
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    row = {'bundle': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion']}
    assert row['version'] == os.environ['APP_VERSION'], f'Built version mismatch: {row}'
    assert row['build'] == os.environ['APP_BUILD'], f'Built build-number mismatch: {row}'
    rows.append(row)
assert len(rows) == 2, 'App and widget must both be present'
pathlib.Path('dist-ios/built-versions.json').write_text(json.dumps(rows, indent=2))
print(json.dumps(rows, indent=2))
