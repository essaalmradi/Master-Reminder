#!/usr/bin/env python3
"""Validate iOS signing inputs without logging private keys, passwords or device IDs."""
import base64, hashlib, json, os, pathlib, plistlib, re, secrets, subprocess, sys
from datetime import datetime, timezone

TEAM = 'KTA6FSZK9V'
BUNDLES = {'APP': 'ly.masterlibya.masterreminder.ios', 'WIDGET': 'ly.masterlibya.masterreminder.ios.widgets'}
root = pathlib.Path(os.environ['RUNNER_TEMP']) / 'master-reminder-ios-signing'
root.mkdir(mode=0o700, exist_ok=True)
report = {'certificate': 'missing', 'profiles': {}, 'installable': False}

def command(args):
    result = subprocess.run(args, capture_output=True)
    if result.returncode:
        # Never include subprocess arguments: they may contain a password.
        raise RuntimeError('Signing validation failed at ' + pathlib.Path(args[0]).name + ' ' + args[1])
    return result.stdout

def output(name, value):
    with open(os.environ['GITHUB_OUTPUT'], 'a') as f: f.write(f'{name}={value}\n')

def decode(name, target):
    raw = os.environ.get(name, '')
    if not raw: return False
    target.write_bytes(base64.b64decode(''.join(raw.split()), validate=True)); target.chmod(0o600)
    return True

try:
    output('ready', 'false')
    p12 = root / 'certificate.p12'
    if not decode('IOS_CERTIFICATE_P12', p12):
        raise RuntimeError('Missing IOS_CERTIFICATE_P12')
    password = os.environ.get('IOS_CERTIFICATE_PASSWORD', '')
    if not password: raise RuntimeError('Missing IOS_CERTIFICATE_PASSWORD')
    keychain = root / 'build.keychain-db'; key_password = secrets.token_urlsafe(32)
    print('::add-mask::' + key_password)
    command(['security', 'create-keychain', '-p', key_password, str(keychain)])
    command(['security', 'set-keychain-settings', '-lut', '21600', str(keychain)])
    command(['security', 'unlock-keychain', '-p', key_password, str(keychain)])
    command(['security', 'import', str(p12), '-P', password, '-A', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain)])
    p12.unlink()
    command(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', key_password, str(keychain)])
    command(['security', 'list-keychains', '-d', 'user', '-s', str(keychain)])
    identities = command(['security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)]).decode()
    match = re.search(r'([A-Fa-f0-9]{40}) "(Apple Distribution: [^"\n]*\(' + TEAM + r'\))"', identities)
    if not match: raise RuntimeError('No valid Apple Distribution identity with private key for the expected team')
    fingerprint, identity = match.groups(); report['certificate'] = 'valid Apple Distribution identity with private key'
    profiles = {}
    devices = []
    for label, bundle in BUNDLES.items():
        secret = f'IOS_{label}_PROVISIONING_PROFILE'; path = root / (label.lower() + '.mobileprovision')
        if not decode(secret, path): report['profiles'][label] = 'missing ' + secret; continue
        profile = plistlib.loads(command(['security', 'cms', '-D', '-i', str(path)]))
        entitlements = profile.get('Entitlements', {})
        if profile.get('TeamIdentifier') != [TEAM]: raise RuntimeError(label + ' profile belongs to another team')
        if entitlements.get('application-identifier') != TEAM + '.' + bundle: raise RuntimeError(label + ' profile has the wrong Bundle ID')
        if entitlements.get('get-task-allow', False) or profile.get('ProvisionsAllDevices') or not profile.get('ProvisionedDevices'):
            raise RuntimeError(label + ' profile must be Ad Hoc distribution for registered devices')
        expiration = profile['ExpirationDate'].replace(tzinfo=timezone.utc)
        if expiration <= datetime.now(timezone.utc): raise RuntimeError(label + ' profile has expired')
        certificates = [hashlib.sha1(c).hexdigest().upper() for c in profile['DeveloperCertificates']]
        if fingerprint.upper() not in certificates: raise RuntimeError(label + ' profile does not match the uploaded distribution certificate')
        devices.append(set(profile['ProvisionedDevices']))
        profiles[bundle] = profile['UUID']
        report['profiles'][label] = {'status': 'valid', 'expires': expiration.date().isoformat(), 'device_count': len(devices[-1])}
        for folder in [pathlib.Path.home() / 'Library/MobileDevice/Provisioning Profiles', pathlib.Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles']:
            folder.mkdir(parents=True, exist_ok=True); target = folder / (profile['UUID'] + '.mobileprovision'); target.write_bytes(path.read_bytes()); target.chmod(0o600)
        with open(os.environ['GITHUB_ENV'], 'a') as f: f.write(f'IOS_{label}_PROFILE_UUID={profile["UUID"]}\n')
    if len(profiles) == 2:
        if not set.intersection(*devices): raise RuntimeError('App and widget profiles share no registered device')
        expected = os.environ.get('IOS_DEVICE_UDID', '')
        if expected and not all(expected in group for group in devices): raise RuntimeError('The requested iPhone is not included in both profiles')
        options = {'method': 'release-testing', 'teamID': TEAM, 'signingStyle': 'manual', 'signingCertificate': identity,
                   'provisioningProfiles': profiles, 'stripSwiftSymbols': True, 'manageAppVersionAndBuildNumber': False, 'thinning': '<none>'}
        (root / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
        output('ready', 'true'); report['ready_to_sign'] = True
    else:
        report['ready_to_sign'] = False
        print('::warning::Certificate verified; Ad Hoc app/widget provisioning profiles are still required. No installable IPA will be claimed.')
    with open(os.environ['GITHUB_ENV'], 'a') as f: f.write('IOS_SIGNING_DIRECTORY=' + str(root) + '\n')
except Exception as exc:
    report['error'] = str(exc)
    print('::error::' + str(exc)); sys.exit_code = 1
finally:
    pathlib.Path('dist-ios').mkdir(exist_ok=True)
    pathlib.Path('dist-ios/signing-status.json').write_text(json.dumps(report, indent=2))
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
        f.write('### iPhone signing inputs\n```json\n' + json.dumps(report, indent=2) + '\n```\n')
if getattr(sys, 'exit_code', 0): sys.exit(1)
