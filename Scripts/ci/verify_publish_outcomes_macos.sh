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

# Compile the exact audio consumer snippets with real Drafty; no source fallback.
python3 - "$result_dir/static.json" <<'AUDIO_UPLOAD_SOURCE'
import hashlib, json, pathlib, re, subprocess, sys

# A source adapter, not a reimplementation of the upload callback. Refuse drift.
def bound_source(name):
    raw = pathlib.Path(name).read_bytes().replace(b"\r\n", b"\n")
    head_blob = subprocess.check_output(["git", "rev-parse", "HEAD:" + name], text=True).strip()
    actual_blob = subprocess.check_output(["git", "hash-object", "--stdin"], input=raw).decode().strip()
    assert actual_blob == head_blob, "Audio source differs from fixed HEAD blob"
    return raw.decode("utf-8"), head_blob

source, source_blob = bound_source("Tinodios/MessageInteractor.swift")
urls, url_blob = bound_source("Tinodios/Utils.swift")
anchor = '                guard let ctrl = serverMessage?.ctrl, ctrl.code == 200, let srvUrl = URL(string: ctrl.getStringParam(for: "url") ?? "") else {'
assert source.count(anchor) == 1, "Audio completion ACK anchor must be unique"
before, after = source.split(anchor)
def audio_case(text):
    matches = re.findall(r"(?ms)^\s*case \.audio:\n(.*?)^\s*case \.file:", text)
    assert len(matches) == 1, "Audio case is missing or ambiguous"
    return matches[0]
initial, completion = audio_case(before), audio_case(after)
methods = re.findall(r"(?ms)^    private static func draftyAudio\(.*?^    \}\n", source)
relativizers = re.findall(r"(?ms)^    func relativize\(from base: URL\).*?^    \}\n", urls)
assert len(methods) == len(relativizers) == 1, "Complete production method must be unique"
method, relativize = methods[0], relativizers[0]
# Preserved verbatim from the pre-fix production blob; never synthesized by replacing the new argument.
legacy_blob = "957739e19a32e8de9f5e5f63b424f78e090cf29e"
legacy_completion = '                    draft = MessageInteractor.draftyAudio(refurl: ref, mimeType: mimeType, data: nil, duration: def.duration!, preview: def.preview!, size: def.data.count)\n'
assert hashlib.sha256(method.encode()).hexdigest() == "1dfd6e361b02deffbffc446a903c9c670302e52f15221753a2450b26ec434971", "Audio helper changed; review the adapter"
assert hashlib.sha256(relativize.encode()).hexdigest() == "987674835af293264a48f0dcada3d783e4f0f22780a2b005e5a7f4e22383397f", "URL helper changed; review the adapter"
assert re.search(r"refurl: (\w+),", initial).group(1) == "ref", "Initial draft must keep its placeholder"
assert re.search(r"refurl: (\w+),", completion).group(1) == "srvUrl", "Completed upload must use its server result"
assert legacy_completion.strip().startswith("draft = MessageInteractor.draftyAudio(")
assert "baseURL: audioBase" in initial and "baseURL: audioBase" in completion, "Audio must use captured original origin"
assert completion.replace("refurl: srvUrl,", "refurl: ref,").replace(", baseURL: audioBase)", ")") == legacy_completion, "Unexpected completion delta"

def wrapper(name, body):
    return """
    static func """ + name + """(ref: URL, srvUrl: URL, duration: Int, preview: Data, data: Data) -> Drafty? {
        let mimeType = "audio/aac"
        let audioBase = Cache.tinode.baseURL(useWebsocketProtocol: false)
        let def = AudioUploadDef(duration: duration, preview: preview, data: data)
        var draft: Drafty?
        var previewData: Data?
""" + body + """
        _ = previewData
        return draft
    }
"""
generated = """// Generated only from the fixed HEAD production source by verify_publish_outcomes_macos.sh.
// Scope: actual upload branch statement + actual helpers + real Drafty; not a UIKit callback.
import Foundation
@testable import TinodeSDK

private struct AudioUploadDef {
    let duration: Int?
    let preview: Data?
    let data: Data
}
private enum Cache {
    static let tinode = AudioBaseURL()
}
private struct AudioBaseURL {
    func baseURL(useWebsocketProtocol: Bool) -> URL? { URL(string: "https://audio-fixture.invalid/") }
}
extension URL {
""" + relativize + """
}
final class MessageInteractor {
    static let sourceBlob = """ + json.dumps(source_blob) + """
    static let originalBlob = """ + json.dumps(legacy_blob) + """
""" + wrapper("completedAudio", completion) + wrapper("initialAudio", initial) + wrapper("legacyCompletedAudio", legacy_completion) + method + """
}
typealias AudioUploadConsumerFixture = MessageInteractor
"""
target = pathlib.Path("build/ci-generated/AudioUploadConsumerFixture.swift")
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(generated, encoding="utf-8", newline="\n")
metadata = {"scope": "Production branch source adapter plus real Drafty; not full UIKit callback",
            "sourceBlob": source_blob, "urlHelperBlob": url_blob, "legacyBlob": legacy_blob,
            "initialSHA256": hashlib.sha256(initial.encode()).hexdigest(),
            "completionSHA256": hashlib.sha256(completion.encode()).hexdigest(),
            "helperSHA256": hashlib.sha256(method.encode()).hexdigest(),
            "adapterSHA256": hashlib.sha256(generated.encode()).hexdigest()}
report_path = pathlib.Path(sys.argv[1])
report = json.loads(report_path.read_text(encoding="utf-8"))
report["audio_upload_source_adapter"] = metadata
report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print("AUDIO_UPLOAD_SOURCE_ADAPTER " + json.dumps(metadata, separators=(",", ":")))
AUDIO_UPLOAD_SOURCE

# Execute complete production reset methods with real UIKit; XIB presentation is a named spy boundary.
python3 - "$result_dir/static.json" <<'VOICE_RESET_SOURCE'
import hashlib, json, pathlib, re, subprocess, sys

name = "Tinodios/widgets/SendMessageBar.swift"
raw = pathlib.Path(name).read_bytes().replace(b"\r\n", b"\n")
source_blob = subprocess.check_output(["git", "rev-parse", "HEAD:" + name], text=True).strip()
actual_blob = subprocess.check_output(["git", "hash-object", "--stdin"], input=raw).decode().strip()
assert actual_blob == source_blob, "Voice reset source differs from fixed HEAD blob"
source = raw.decode("utf-8")
expected = {
    "captureRecordingGestureOrigin": "b17814db36553753c00d9a28d928272459170ac94ad16b48ebd23223c48b85fa",
    "resetRecordingGesture": "c1d456314cf8e554b1e2e7b5fc10ebc05759eacb31839eee4ed90d864c5db1bf",
    "resetRecordingState": "b3d2e8b91bb1109d5a36260c1bb04af28ca2242b0bd13ebcb2c56a07c1aa27b5",
}
methods = []
for method, digest in expected.items():
    matches = re.findall(r"(?ms)^    (?:private )?func " + method + r"\(\) \{\n.*?^    \}\n", source)
    assert len(matches) == 1, "Voice reset method is missing or ambiguous: " + method
    assert hashlib.sha256(matches[0].encode()).hexdigest() == digest, "Voice reset method drift: " + method
    methods.append(matches[0])
assert source.count("private var sendButtonConstrains: CGPoint?") == 1, "Optional snapshot declaration changed"
assert source.count("self.captureRecordingGestureOrigin()") == 1, "Gesture must use the captured production snapshot"
began = re.findall(r"(?ms)^        case \.began:\n(.*?)^        case \.ended:", source)
assert len(began) == 1 and "self.captureRecordingGestureOrigin()" in began[0], "Capture must run in actual gesture begin"
gesture = re.findall(r"(?ms)^    @IBAction func longPressed\(sender: UILongPressGestureRecognizer\) \{\n.*?^    \}\n", source)
assert len(gesture) == 1, "Complete gesture consumer must be unique"
changed = re.findall(r"(?ms)^        case \.changed:\n(.*?)^        default:", gesture[0])
assert len(changed) == 1 and changed[0].lstrip().startswith(
    "guard recordingStarted, let origin = sendButtonConstrains else { return }"), "Changed gesture must bind snapshot before movement"
assert "origin.x + dX" in changed[0] and "origin.y + dY" in changed[0], "Movement must use the bound snapshot"
assert not re.search(r"sendButtonConstrains\s*[!.]", source), "No optional snapshot force unwrap or direct member access"
action = re.findall(r"(?ms)^    func audioBarState\(_ state: AudioBarAction\) \{\n.*?^    \}\n", source)
assert len(action) == 1 and action[0].count("self.resetRecordingGesture()") == 1, "Lock/cancel must use actual reset"
normal = re.findall(r"(?m)^        static let kButtonSizeNormal: CGFloat = [0-9]+$", source)
assert len(normal) == 1, "Production button size must be unique"
generated = '''// Generated from fixed HEAD complete methods; no XIB or chat-page claim.
import UIKit

final class SendMessageBarResetSource: UIView {
    static let sourceBlob = ''' + json.dumps(source_blob) + '''
    private enum Constants {
''' + normal[0] + '''
    }
    enum AudioBarState { case hidden }
    var sendButtonConstrains: CGPoint?
    var recordingStarted = false
    var audioLocked = false
    let verticalSliderView = UIView()
    let horizontalSliderView = UIView()
    private let button = UIView()
    lazy var sendButtonHorizontal = button.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -26)
    lazy var sendButtonVertical = button.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -28)
    lazy var sendButtonSize = button.widthAnchor.constraint(equalToConstant: Constants.kButtonSizeNormal)
    private(set) var hiddenPresentationCalls = 0
    var normalButtonSize: CGFloat { Constants.kButtonSizeNormal }
    // Test admission only: executes the exact private production capture method below.
    func captureCurrentLayoutForGesture() { captureRecordingGestureOrigin() }
    // Explicit presentation spy: the real showAudioBar/XIB is NOT adapted or executed here.
    private func showAudioBar(_ state: AudioBarState) { hiddenPresentationCalls += 1 }
''' + "\n".join(methods) + "}\n"
target = pathlib.Path("build/ci-generated/SendMessageBarResetSource.swift")
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(generated, encoding="utf-8", newline="\n")
metadata = {"scope": "Complete production capture/reset methods + real UIKit; showAudioBar spy, no XIB/page",
            "sourceBlob": source_blob, "methodSHA256": expected,
            "gestureConsumerSHA256": hashlib.sha256(gesture[0].encode()).hexdigest(),
            "gestureConsumerCheck": "source only: full consumer guard and no direct optional member access",
            "adapterSHA256": hashlib.sha256(generated.encode()).hexdigest()}
report_path = pathlib.Path(sys.argv[1])
report = json.loads(report_path.read_text(encoding="utf-8"))
report["voice_reset_source_adapter"] = metadata
report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print("VOICE_RESET_SOURCE_ADAPTER " + json.dumps(metadata, separators=(",", ":")))
VOICE_RESET_SOURCE

xcodebuild test -workspace Tinodios.xcworkspace -scheme TinodeSDK \
  -configuration Debug -destination "platform=iOS Simulator,id=$sim_id" \
  -parallel-testing-enabled NO \
  -derivedDataPath "$result_dir/DerivedData" -resultBundlePath "$result_dir/sdk.xcresult" \
  -only-testing:TinodeSDKTests/TinodeSDKTests \
  HOST_NAME=127.0.0.1:9 USE_TLS=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$result_dir/sdk.log"
# Real VLC dependency probe: use installed simulator headers, never an online/latest SDK guess.
vlc_pod_evidence="$(python3 - <<'VLC_POD_EVIDENCE'
import hashlib, json, pathlib, plistlib, re
root = pathlib.Path("Pods/MobileVLCKit")
# Ordinary spec-repository pods need not appear in Pods/Local Podspecs.
# Read only the two exact CocoaPods lock sections needed here; reject unknown formatting.
def section(text, name):
    lines = text.splitlines()
    starts = [i for i, line in enumerate(lines) if line == name + ":"]
    assert len(starts) == 1, "Missing or duplicate required CocoaPods lock section"
    body = []
    for line in lines[starts[0] + 1:]:
        if line and not line.startswith(" "):
            break
        body.append(line)
    return "\n".join(body)

locks = []
for name in ("Podfile.lock", "Pods/Manifest.lock"):
    data = pathlib.Path(name).read_bytes()
    text = data.decode("utf-8")
    versions = re.findall(r"^  - MobileVLCKit \(([^()\r\n]+)\):?$", section(text, "PODS"), re.M)
    checksums = re.findall(r"^  MobileVLCKit: ([0-9a-f]{40})$", section(text, "SPEC CHECKSUMS"), re.M)
    assert len(versions) == len(checksums) == 1, "Missing or ambiguous MobileVLCKit lock evidence"
    locks.append({"file": name, "sha256": hashlib.sha256(data).hexdigest(),
                  "podVersion": versions[0], "specChecksum": checksums[0]})
assert locks[0]["podVersion"] == locks[1]["podVersion"] == "3.6.0", "VLC lock version mismatch"
assert locks[0]["specChecksum"] == locks[1]["specChecksum"] == "8fe98ae53b7464f32e4bdf527cc7d53053e4d3a5", "VLC spec checksum mismatch"
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
print(json.dumps({"podVersion": locks[0]["podVersion"], "specChecksum": locks[0]["specChecksum"],
    "locks": locks, "archiveVerification": "NOT_PERFORMED; spec checksum is not an archive hash",
    "simulatorArchitectures": entry["SupportedArchitectures"], "headers": headers,
    "frameworkVersion": bundle.get("CFBundleShortVersionString", ""),
    "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest()}, separators=(",", ":")))
VLC_POD_EVIDENCE
)"
# xcodebuild forwards TEST_RUNNER_ variables without the prefix; the actual hosted test rejects missing evidence.
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
  -only-testing:TinodiosUITests/MediaRecorderLifecycleTests \
  -only-testing:TinodiosUITests/SendMessageBarResetTests \
  -only-testing:TinodiosVLCProbeTests/VLCPlaybackProbeTests \
  -only-testing:TinodiosVoiceLayoutTests/VoiceLayoutTests \
  -only-testing:TinodiosVoiceLayoutTests/ChatScrollTests \
  -only-testing:TinodiosVoiceLayoutTests/CoreListLayoutTests \
  HOST_NAME=127.0.0.1:9 USE_TLS=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$result_dir/storage.log"
unset TEST_RUNNER_CLAW_VLC_POD_EVIDENCE
# Real App navigation is separate from the selected SDK/storage methods and 4 VLC measurement methods.
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
