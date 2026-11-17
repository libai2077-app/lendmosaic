#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
: "${RUNNER_TEMP:?Requires GitHub-hosted macOS runner}"
: "${BUILD_NUMBER:?Missing build_number}"
: "${UPLOAD_IPA:?Missing upload input}"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo 'Build number must be a positive integer.' >&2; exit 1; }
[[ "$UPLOAD_IPA" == true || "$UPLOAD_IPA" == false ]] || exit 1
OUT="$RUNNER_TEMP/ios-release-output"
STATE="$RUNNER_TEMP/ios-ci-signing"
WORK="$(mktemp -d "$RUNNER_TEMP/ios-build.XXXXXXXX")"
mkdir -p "$OUT"
cleanup() {
  local code=$?
  trap - EXIT
  ruby "$ROOT/prepare-signing.rb" cleanup || echo 'Warning: cleanup failed; see final cleanup step.' >&2
  rm -rf "$WORK"
  exit "$code"
}
trap cleanup EXIT

# A failing parser terminates before any secrets are imported. Never source/eval YAML.
ruby "$ROOT/load-config.rb" > "$WORK/config.env"
while IFS='=' read -r key value; do export "$key=$value"; done < "$WORK/config.env"
if [[ -n "$XCODE_DEVELOPER_DIR" ]]; then export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"; fi
xcodebuild -version | tee "$OUT/xcode-version.txt"
xcodebuild -showsdks > "$OUT/sdks.txt"

case "$PROJECT_PATH" in
  *.xcworkspace) CONTAINER=(-workspace "$PROJECT_PATH");;
  *.xcodeproj) CONTAINER=(-project "$PROJECT_PATH");;
  *) exit 1;;
esac
ARGS=("${CONTAINER[@]}" -scheme "$SCHEME" -configuration Release
  -destination 'generic/platform=iOS' -derivedDataPath "$WORK/DerivedData"
  "DEVELOPMENT_TEAM=$TEAM_ID" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
xcodebuild "${ARGS[@]}" -showBuildSettings -json > "$WORK/settings.json"
python3 - "$WORK/settings.json" <<'PY'
import json,sys,os,plistlib,pathlib
rows=json.load(open(sys.argv[1])); apps=[r['buildSettings'] for r in rows if r['buildSettings'].get('WRAPPER_EXTENSION')=='app']
assert len(apps)==1, 'Exactly one App target is required'
assert not any(r['buildSettings'].get('WRAPPER_EXTENSION')=='appex' for r in rows), 'Extensions need per-target signing; not supported'
app=apps[0]
assert app.get('PRODUCT_BUNDLE_IDENTIFIER')==os.environ['BUNDLE_ID'], 'Project Bundle ID mismatch'
raw=app.get('CODE_SIGN_ENTITLEMENTS','')
e={}
if raw:
    path=(pathlib.Path(app['SRCROOT'])/raw).resolve()
    assert path.is_relative_to(pathlib.Path.cwd().resolve()), 'Entitlements path outside repository'
    with path.open('rb') as f: e=plistlib.load(f)
if os.environ['CLOUDKIT_ENABLED']=='true':
    assert raw, 'Target has no CODE_SIGN_ENTITLEMENTS'
    assert path==pathlib.Path(os.environ['ENTITLEMENTS_PATH']).resolve(), 'Configured entitlements are not the target entitlements'
    assert os.environ['CLOUDKIT_CONTAINER_ID'] in e.get('com.apple.developer.icloud-container-identifiers',[]), 'Source CloudKit container mismatch'
    assert 'CloudKit' in e.get('com.apple.developer.icloud-services',[]), 'Source CloudKit service missing'
else:
    # Do not silently omit checks when the project still declares CloudKit.
    assert 'CloudKit' not in e.get('com.apple.developer.icloud-services',[]), 'Project uses CloudKit: enable it in app-config.yml'
PY

ruby "$ROOT/prepare-signing.rb"
# Avoid accidental environment dumps by project build scripts.
unset BUILD_CERTIFICATE_BASE64 BUILD_PROVISION_PROFILE_BASE64 P12_PASSWORD ASC_PRIVATE_KEY_BASE64
PROFILE_UUID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["uuid"])' "$STATE/signing.json")"
SIGNING_IDENTITY="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["fingerprint"])' "$STATE/signing.json")"
export PROFILE_UUID SIGNING_IDENTITY

echo '========== 1. Compile =========='
xcodebuild "${ARGS[@]}" CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$OUT/compile.log"
echo '========== 2. Archive =========='
ARCHIVE="$WORK/App.xcarchive"
xcodebuild "${ARGS[@]}" -archivePath "$ARCHIVE" CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGNING_IDENTITY" \
  "PROVISIONING_PROFILE_SPECIFIER=$PROFILE_UUID" archive 2>&1 | tee "$OUT/archive.log"

python3 - "$WORK/ExportOptions.plist" <<'PY'
import os,sys,plistlib
e=os.environ
p={'method':'app-store-connect','destination':'export','signingStyle':'manual',
   'signingCertificate':e['SIGNING_IDENTITY'],'teamID':e['TEAM_ID'],
   'manageAppVersionAndBuildNumber':False,'provisioningProfiles':{e['BUNDLE_ID']:e['PROFILE_UUID']}}
if e['CLOUDKIT_ENABLED']=='true': p['iCloudContainerEnvironment']='Production'
with open(sys.argv[1],'wb') as f: plistlib.dump(p,f)
PY
echo '========== 3. Export =========='
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/export" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" 2>&1 | tee "$OUT/export.log"
shopt -s nullglob
IPAS=("$WORK/export/"*.ipa)
[[ ${#IPAS[@]} -eq 1 ]] || { echo 'Expected exactly one IPA.' >&2; exit 1; }
IPA="${IPAS[0]}"
mkdir "$WORK/inspect"
/usr/bin/ditto -x -k "$IPA" "$WORK/inspect"
APPS=("$WORK/inspect/Payload/"*.app)
[[ ${#APPS[@]} -eq 1 ]] || exit 1
APP="${APPS[0]}"
# A second guard catches extensions not listed by showBuildSettings.
if [[ -n "$(find "$APP" -type d \( -name '*.appex' -o -name '*.app' \) ! -path "$APP" -print -quit)" ]]; then
  echo 'Embedded app/extension requires a multi-target workflow.' >&2; exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/codesign -d --entitlements :- "$APP" > "$WORK/signed.plist" 2> "$WORK/codesign-info.txt"
python3 - "$WORK/signed.plist" "$APP/Info.plist" "$STATE/signing.json" <<'PY'
import plistlib,sys,os,json
with open(sys.argv[1],'rb') as f: e=plistlib.load(f)
with open(sys.argv[2],'rb') as f: info=plistlib.load(f)
s=json.load(open(sys.argv[3]))
assert info['CFBundleIdentifier']==os.environ['BUNDLE_ID'], 'IPA Bundle ID mismatch'
assert str(info['CFBundleVersion'])==os.environ['BUILD_NUMBER'], 'Build number not applied; check hard-coded Info.plist'
assert e.get('com.apple.developer.team-identifier')==os.environ['TEAM_ID'], 'Signed Team mismatch'
assert e.get('application-identifier')==s['app_identifier'], 'Signed App ID mismatch'
assert not e.get('get-task-allow',False), 'Debug signing forbidden'
if os.environ['CLOUDKIT_ENABLED']=='true':
    assert e.get('com.apple.developer.icloud-container-environment')=='Production', 'CloudKit must be Production'
    assert os.environ['CLOUDKIT_CONTAINER_ID'] in e.get('com.apple.developer.icloud-container-identifiers',[]), 'Signed container mismatch'
    assert 'CloudKit' in e.get('com.apple.developer.icloud-services',[]), 'Signed CloudKit service missing'
PY
cp "$IPA" "$OUT/$APP_NAME.ipa"
if [[ -d "$ARCHIVE/dSYMs" ]]; then tar -czf "$OUT/dSYMs.tar.gz" -C "$ARCHIVE" dSYMs; fi
(cd "$OUT" && shasum -a 256 "$APP_NAME.ipa" > ipa.sha256)
printf 'app=%s\nbundle_id=%s\nteam=%s\nbuild=%s\ncommit=%s\ncloudkit=%s\nupload_requested=%s\n' \
  "$APP_NAME" "$BUNDLE_ID" "$TEAM_ID" "$BUILD_NUMBER" "${GITHUB_SHA:-unknown}" "$CLOUDKIT_ENABLED" "$UPLOAD_IPA" > "$OUT/build-info.txt"
if [[ "$UPLOAD_IPA" == true ]]; then
  export API_PRIVATE_KEYS_DIR="$STATE/private_keys"
  AUTH=(--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID")
  echo '========== 4. Apple validation =========='
  xcrun altool --validate-app -f "$IPA" -t ios "${AUTH[@]}" 2>&1 | tee "$OUT/validate.log"
  echo '========== 5. Upload =========='
  xcrun altool --upload-app -f "$IPA" -t ios "${AUTH[@]}" 2>&1 | tee "$OUT/upload.log"
  echo 'upload_command=succeeded_processing_not_verified' >> "$OUT/build-info.txt"
  echo 'Upload command succeeded. Check processing in App Store Connect. No review submitted.'
else
  echo 'IPA exported. Apple validation and upload skipped.'
fi
