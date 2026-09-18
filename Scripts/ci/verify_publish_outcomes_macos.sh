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
printf '%s\n' "$sim_id" > "$result_dir/simulator-id.txt"
python3 -B Scripts/ci/run_static_policies.py --report "$result_dir/static.json"
pod install
python3 - <<'PY'
import pathlib, plistlib
path = pathlib.Path("Tinodios/Settings.bundle/Acknowledgements.plist")
with path.open("rb") as stream:
    value = plistlib.load(stream)
assert isinstance(value.get("PreferenceSpecifiers"), list), "CocoaPods license resource is invalid"
PY

# Existing Firebase policy rejects this non-production fixture for real push/release.
created_fixture=false
cleanup_fixture() {
  local original_status=$?
  local export_status=0
  for result_bundle in "$result_dir"/*.xcresult; do
    [[ -d "$result_bundle" ]] || continue
    xcrun xcresulttool get test-results summary --path "$result_bundle" \
      > "${result_bundle%.xcresult}-summary.json" 2> "${result_bundle%.xcresult}-summary.err" || true
  done
  if python3 - "$result_dir" <<'EXPORT_NAVIGATION'
import hashlib, json, pathlib, subprocess, sys, time
result = pathlib.Path(sys.argv[1]).resolve()
bundle = result / "navigation.xcresult"
output = result / "navigation-attachments"
report = {"status": "NOT_RUN", "source": "navigation.xcresult",
          "scope": "Original XCTest attachments only; no image conversion or reconstruction",
          "commands": [], "screenshots": []}
exit_code = 0

def invoke(stage, arguments, timeout):
    started = time.monotonic()
    try:
        completed = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        report["commands"].append({"stage": stage, "returncode": None, "timeout_seconds": timeout,
                                   "elapsed_seconds": round(time.monotonic() - started, 6)})
        raise
    report["commands"].append({"stage": stage, "returncode": completed.returncode,
                               "elapsed_seconds": round(time.monotonic() - started, 6)})
    return completed

try:
    if bundle.is_dir():
        report["status"] = "FAIL"
        # Xcode 16.3 documents this command; runtime help is authoritative for this runner.
        help_result = invoke("help", ["xcrun", "xcresulttool", "help", "export", "attachments"], 30)
        (result / "navigation-export-help.txt").write_text(help_result.stdout, encoding="utf-8")
        (result / "navigation-export-help.err").write_text(help_result.stderr, encoding="utf-8")
        help_text = help_result.stdout + help_result.stderr
        if help_result.returncode != 0 or not all(flag in help_text for flag in ("--path", "--output-path")):
            raise RuntimeError("Current xcresulttool help does not confirm required attachment export arguments")
        output.mkdir(exist_ok=False)
        exported = invoke("export", ["xcrun", "xcresulttool", "export", "attachments",
                          "--path", str(bundle), "--output-path", str(output)], 60)
        (result / "navigation-export.stdout").write_text(exported.stdout, encoding="utf-8")
        (result / "navigation-export.stderr").write_text(exported.stderr, encoding="utf-8")
        if exported.returncode != 0:
            raise RuntimeError("xcresulttool attachment export failed")
        for path in sorted(output.rglob("*.png")):
            if not path.resolve().is_relative_to(output):
                raise RuntimeError("Exported screenshot escaped attachment directory")
            data = path.read_bytes()
            if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
                raise RuntimeError("Exported screenshot is not a PNG")
            width, height = int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
            if width <= 0 or height <= 0:
                raise RuntimeError("Exported screenshot has no pixels")
            report["screenshots"].append({"file": path.relative_to(output).as_posix(),
                "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                "width": width, "height": height})
        if not report["screenshots"]:
            raise RuntimeError("Attachment export produced no viewable XCTest screenshots")
        report["status"] = "PASS_EXPORTED_ONLY"
    else:
        report["reason"] = "Navigation result bundle was not produced"
except Exception as error:
    report.update(status="FAIL", failure=str(error), error_type=type(error).__name__)
    exit_code = 1
finally:
    (result / "navigation-export-status.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print("Navigation attachment export: " + report["status"])
raise SystemExit(exit_code)
EXPORT_NAVIGATION
  then
    export_status=0
  else
    export_status=$?
  fi
  if [[ "$created_fixture" == true ]]; then
    rm -f -- "$repo_dir/GoogleService-Info.plist"
  fi
  # Never replace an SDK/storage/navigation test failure with an export result.
  if [[ "$original_status" -ne 0 ]]; then
    exit "$original_status"
  fi
  exit "$export_status"
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
  -parallel-testing-enabled NO \
  -derivedDataPath "$result_dir/DerivedData" -resultBundlePath "$result_dir/sdk.xcresult" \
  -only-testing:TinodeSDKTests/TinodeSDKTests \
  HOST_NAME=127.0.0.1:9 USE_TLS=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$result_dir/sdk.log"
xcodebuild test -workspace Tinodios.xcworkspace -scheme Tinodios \
  -configuration Debug -destination "platform=iOS Simulator,id=$sim_id" \
  -parallel-testing-enabled NO \
  -derivedDataPath "$result_dir/DerivedData" -resultBundlePath "$result_dir/storage.xcresult" \
  -only-testing:TinodiosUITests/PublishStorageTests \
  -only-testing:TinodiosUITests/LocalMigrationTests \
  -only-testing:TinodiosUITests/IdentityFlowTests \
  -only-testing:TinodiosUITests/ConversationRemovalTests \
  -only-testing:TinodiosUITests/PublicDirectoryTests \
  -only-testing:TinodiosUITests/SecondaryUIStateTests \
  -only-testing:TinodiosUITests/OwnedImageTests \
  HOST_NAME=127.0.0.1:9 USE_TLS=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$result_dir/storage.log"
# Real App navigation is reported separately from the 181 SDK/storage/business methods.
# Same selected device and closed loopback endpoint; no login or OTP submission.
xcodebuild test -workspace Tinodios.xcworkspace -scheme Tinodios \
  -configuration Debug -destination "platform=iOS Simulator,id=$sim_id" \
  -parallel-testing-enabled NO \
  -derivedDataPath "$result_dir/DerivedData" -resultBundlePath "$result_dir/navigation.xcresult" \
  -only-testing:TinodiosUITests/IdentityNavigationUITests \
  HOST_NAME=127.0.0.1:9 USE_TLS=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$result_dir/navigation.log"
python3 - "$result_dir" <<'PY'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1]) / "DerivedData/Build/Products/Debug-iphonesimulator/Tinodios.app/Settings.bundle/Acknowledgements.plist"
with path.open("rb") as stream:
    value = plistlib.load(stream)
assert isinstance(value.get("PreferenceSpecifiers"), list), "Bundled license resource is invalid"
print("Bundled CocoaPods license resource parsed")
PY
echo "Simulator results: $result_dir (physical device, APNs and real server not tested)"
