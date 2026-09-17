#!/usr/bin/env bash
# Local simulator checks only. No remote CI dispatch, signing or release archive.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_dir"
command -v xcodebuild >/dev/null
command -v xcrun >/dev/null
command -v python3 >/dev/null
command -v pod >/dev/null

sim_id="${CLAW_SIMULATOR_ID:-}"
if [[ -z "$sim_id" ]]; then
  sim_id="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if x.get("isAvailable") and x["name"].startswith("iPhone")), ""))')"
fi
[[ -n "$sim_id" ]] || { echo "No iPhone simulator available" >&2; exit 1; }
result_dir="$repo_dir/build/ios-01-a-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$result_dir"
python3 -B Scripts/ci/run_static_policies.py --report "$result_dir/static.json"
pod install

# Existing Firebase policy rejects this non-production fixture for real push/release.
created_fixture=false
cleanup_fixture() {
  if [[ "$created_fixture" == true ]]; then
    rm -f -- "$repo_dir/GoogleService-Info.plist"
  fi
}
trap cleanup_fixture EXIT
if [[ ! -f GoogleService-Info.plist ]]; then
  python3 - <<'PY'
import plistlib
with open("GoogleService-Info.plist", "xb") as f:
    plistlib.dump({
        "CLIENT_ID": "0-placeholder.apps.googleusercontent.com",
        "REVERSED_CLIENT_ID": "com.googleusercontent.apps.0-placeholder",
        "API_KEY": "placeholder-api-key", "GCM_SENDER_ID": "000000000000",
        "PLIST_VERSION": "1", "BUNDLE_ID": "app.veilping.clawoschat",
        "PROJECT_ID": "claw-os-placeholder", "STORAGE_BUCKET": "claw-os-placeholder.appspot.com",
        "GOOGLE_APP_ID": "1:000000000000:ios:0000000000000000000000",
        "IS_ADS_ENABLED": False, "IS_ANALYTICS_ENABLED": False,
        "IS_APPINVITE_ENABLED": False, "IS_GCM_ENABLED": False, "IS_SIGNIN_ENABLED": False
    }, f)
PY
  created_fixture=true
fi

xcodebuild test -workspace Tinodios.xcworkspace -scheme TinodeSDK \
  -configuration Debug -destination "platform=iOS Simulator,id=$sim_id" \
  -derivedDataPath "$result_dir/DerivedData" -resultBundlePath "$result_dir/sdk.xcresult" \
  -only-testing:TinodeSDKTests/TinodeSDKTests \
  HOST_NAME=127.0.0.1:9 USE_TLS=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$result_dir/sdk.log"
xcodebuild test -workspace Tinodios.xcworkspace -scheme Tinodios \
  -configuration Debug -destination "platform=iOS Simulator,id=$sim_id" \
  -derivedDataPath "$result_dir/DerivedData" -resultBundlePath "$result_dir/storage.xcresult" \
  -only-testing:TinodiosUITests/PublishStorageTests \
  -only-testing:TinodiosUITests/LocalMigrationTests \
  HOST_NAME=127.0.0.1:9 USE_TLS=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$result_dir/storage.log"
echo "Simulator results: $result_dir (physical device, APNs and real server not tested)"
