"""Reads decoded mobileprovision plist on stdin; emits only signing metadata."""
import datetime
import hashlib
import json
import os
import plistlib
import re
import sys


def validate(p, env):
    e = p['Entitlements']
    assert re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', p['UUID']), 'Invalid UUID'
    assert env['TEAM_ID'] in p.get('TeamIdentifier', []), 'Profile Team mismatch'
    expiry = p['ExpirationDate']
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=datetime.timezone.utc)
    assert expiry > datetime.datetime.now(datetime.timezone.utc), 'Expired profile'
    assert not e.get('get-task-allow', False), 'Development profile forbidden'
    assert 'ProvisionedDevices' not in p and not p.get('ProvisionsAllDevices', False), 'App Store profile required'
    app = e['application-identifier']
    assert any(app == prefix + '.' + env['BUNDLE_ID'] for prefix in p['ApplicationIdentifierPrefix']), 'App ID mismatch'
    if env['CLOUDKIT_ENABLED'] == 'true':
        assert env['CLOUDKIT_CONTAINER_ID'] in e.get('com.apple.developer.icloud-container-identifiers', []), 'CloudKit container missing'
        allowed = e.get('com.apple.developer.icloud-container-environment', [])
        assert 'Production' in ([allowed] if isinstance(allowed, str) else allowed), 'Production not authorized'
        services = e.get('com.apple.developer.icloud-services')
        assert (
            services == '*'
            or (isinstance(services, list) and 'CloudKit' in services)
        ), 'CloudKit service missing'
    return {'uuid': p['UUID'], 'app_identifier': app,
            'fingerprints': [hashlib.sha1(c).hexdigest().upper() for c in p['DeveloperCertificates']]}


if __name__ == '__main__':
    try:
        print(json.dumps(validate(plistlib.loads(sys.stdin.buffer.read()), os.environ)))
    except Exception as exc:
        # Do not log the decoded plist, profile certificate bytes or environment.
        print('Profile validation failed: ' + str(exc), file=sys.stderr)
        sys.exit(1)
