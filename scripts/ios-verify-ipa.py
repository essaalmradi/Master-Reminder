#!/usr/bin/env python3
import hashlib, json, os, pathlib, plistlib, subprocess, tempfile, zipfile
ipa = next(pathlib.Path('dist-ios').glob('*.ipa'))
with tempfile.TemporaryDirectory() as temp:
    with zipfile.ZipFile(ipa) as archive: archive.extractall(temp)
    app = next((pathlib.Path(temp) / 'Payload').glob('*.app'))
    profiles = []
    for bundle in [app, *app.glob('PlugIns/*.appex')]:
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(bundle / 'embedded.mobileprovision')]))
        assert info['CFBundleShortVersionString'] == os.environ['APP_VERSION']
        assert info['CFBundleVersion'] == os.environ['APP_BUILD']
        assert profile['Entitlements']['application-identifier'] == 'KTA6FSZK9V.' + info['CFBundleIdentifier']
        assert not profile['Entitlements'].get('get-task-allow', False)
        profiles.append(set(profile['ProvisionedDevices']))
    assert len(profiles) == 2 and set.intersection(*profiles), 'Missing widget or mismatched device profiles'
report = {'version': os.environ['APP_VERSION'], 'build': os.environ['APP_BUILD'], 'sha': os.environ['GITHUB_SHA'],
          'installable': True, 'distribution': 'Ad Hoc registered devices', 'ipa_sha256': hashlib.sha256(ipa.read_bytes()).hexdigest()}
pathlib.Path('dist-ios/release.json').write_text(json.dumps(report, indent=2))
pathlib.Path('dist-ios/INSTALLATION-STATUS.txt').write_text('SIGNED Ad Hoc IPA. Installable only on devices included in both profiles.\nPhysical-device sound and authorization still require testing on the iPhone.\n')
