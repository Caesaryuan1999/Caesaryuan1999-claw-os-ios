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
  local result_kind
  for result_kind in navigation storage; do
  if python3 - "$result_dir" "$result_kind" <<'EXPORT_ATTACHMENTS'
import hashlib, json, pathlib, subprocess, sys, time
result = pathlib.Path(sys.argv[1]).resolve()
kind = sys.argv[2]
assert kind in ("navigation", "storage")
bundle = result / (kind + ".xcresult")
output = result / (kind + "-attachments")
report = {"status": "NOT_RUN", "source": bundle.name,
          "scope": "Original XCTest attachments only; no image conversion or reconstruction",
          "safety": "NOT_ASSESSED_BY_EXPORT",
          "commands": [], "screenshots": [], "json_attachments": [], "files": []}
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
        (result / (kind + "-export-help.txt")).write_text(help_result.stdout, encoding="utf-8")
        (result / (kind + "-export-help.err")).write_text(help_result.stderr, encoding="utf-8")
        help_text = help_result.stdout + help_result.stderr
        if help_result.returncode != 0 or not all(flag in help_text for flag in ("--path", "--output-path")):
            raise RuntimeError("Current xcresulttool help does not confirm required attachment export arguments")
        output.mkdir(exist_ok=False)
        exported = invoke("export", ["xcrun", "xcresulttool", "export", "attachments",
                          "--path", str(bundle), "--output-path", str(output)], 60)
        (result / (kind + "-export.stdout")).write_text(exported.stdout, encoding="utf-8")
        (result / (kind + "-export.stderr")).write_text(exported.stderr, encoding="utf-8")
        if exported.returncode != 0:
            raise RuntimeError("xcresulttool attachment export failed")
        for path in sorted(output.rglob("*")):
            if not path.resolve().is_relative_to(output):
                raise RuntimeError("Exported attachment escaped attachment directory")
            if not path.is_file():
                continue
            data = path.read_bytes()
            entry = {"file": path.relative_to(output).as_posix(),
                     "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
            report["files"].append(entry)
            if path.suffix.lower() == ".json":
                value = json.loads(data)
                report["json_attachments"].append({**entry, "vlc_probe_observation":
                    isinstance(value, dict) and "fixture" in value and "dependencyEvidence" in value})
            if path.suffix.lower() != ".png":
                continue
            if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
                raise RuntimeError("Exported screenshot is not a PNG")
            width, height = int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
            if width <= 0 or height <= 0:
                raise RuntimeError("Exported screenshot has no pixels")
            report["screenshots"].append({**entry, "width": width, "height": height})
        if not report["screenshots"]:
            raise RuntimeError("Attachment export produced no viewable XCTest screenshots")
        if kind == "storage" and not any(item["vlc_probe_observation"] for item in report["json_attachments"]):
            raise RuntimeError("Storage export produced no VLC probe observation JSON")
        report["status"] = "PASS_EXPORTED_ONLY"
    else:
        report["reason"] = kind.capitalize() + " result bundle was not produced"
except Exception as error:
    report.update(status="FAIL", failure=str(error), error_type=type(error).__name__)
    exit_code = 1
finally:
    (result / (kind + "-export-status.json")).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(kind.capitalize() + " attachment export: " + report["status"])
raise SystemExit(exit_code)
EXPORT_ATTACHMENTS
  then
    :
  else
    export_status=1
  fi
  done
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
# Real VLC dependency probe: use installed simulator headers, never an online/latest SDK guess.
vlc_pod_evidence="$(python3 - <<'VLC_POD_EVIDENCE'
import hashlib, json, pathlib, plistlib
root = pathlib.Path("Pods/MobileVLCKit")
spec = json.loads(pathlib.Path("Pods/Local Podspecs/MobileVLCKit.podspec.json").read_text())
assert spec["version"] == "3.6.0", "VLC probe requires the frozen pod version"
assert spec["source"]["sha256"] == "1a5077beeb7bf943a3fbbb91523752e50a10d490a3046cb9808d906784ddbc36", "Unexpected VLC pod archive contract"
frameworks = list(root.glob("*.xcframework"))
assert len(frameworks) == 1, "Expected one installed MobileVLCKit xcframework"
xcframework = frameworks[0]
info = plistlib.loads((xcframework / "Info.plist").read_bytes())
slices = [s for s in info["AvailableLibraries"] if s.get("SupportedPlatform") == "ios"
          and s.get("SupportedPlatformVariant") == "simulator"]
assert len(slices) == 1, "Expected one iOS simulator slice"
entry = slices[0]
framework = xcframework / entry["LibraryIdentifier"] / entry["LibraryPath"]
assert framework.resolve().is_relative_to(root.resolve()), "VLC slice escaped pod directory"
headers = []
for name, expected in [("VLCMedia.h", "statistics"), ("VLCMediaPlayer.h", "saveVideoSnapshotAt:"),
                       ("VLCLibrary.h", "changeset")]:
    path = framework / "Headers" / name
    data = path.read_bytes()
    assert expected in data.decode("utf-8"), "Installed VLC header lacks a required probe API"
    headers.append({"name": name, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
bundle = plistlib.loads((framework / "Info.plist").read_bytes())
binary = framework / bundle["CFBundleExecutable"]
assert binary.resolve().is_relative_to(root.resolve()), "VLC binary escaped pod directory"
print(json.dumps({"podVersion": spec["version"], "archiveSHA256": spec["source"]["sha256"],
    "simulatorArchitectures": entry["SupportedArchitectures"], "headers": headers,
    "frameworkVersion": bundle.get("CFBundleShortVersionString", ""),
    "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest()}, separators=(",", ":")))
VLC_POD_EVIDENCE
)"
# xcodebuild forwards TEST_RUNNER_ variables to the test runner without that prefix.
export TEST_RUNNER_CLAW_VLC_POD_EVIDENCE="$vlc_pod_evidence"
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
  -only-testing:TinodiosUITests/VLCPlaybackProbeTests \
  HOST_NAME=127.0.0.1:9 USE_TLS=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$result_dir/storage.log"
unset TEST_RUNNER_CLAW_VLC_POD_EVIDENCE
# Real App navigation is separate from 196 existing native methods and 4 VLC measurement methods.
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
