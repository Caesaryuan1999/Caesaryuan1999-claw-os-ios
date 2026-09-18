"""Execute the actual CI extractor against safe isolated real Git fixtures; no Swift claim."""
import hashlib
import json
import re
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
REPORT = Path(__file__).resolve().parent
script = (ROOT / "Scripts/ci/verify_publish_outcomes_macos.sh").read_text(encoding="utf-8")
chunks = re.findall(r"(?ms)^python3 - \"\$result_dir/static.json\" <<'AUDIO_UPLOAD_SOURCE'\n(.*?)^AUDIO_UPLOAD_SOURCE$", script)
assert len(chunks) == 1
extractor = chunks[0]
compile(extractor, "<actual CI source extractor>", "exec")
source = (ROOT / "Tinodios/MessageInteractor.swift").read_text(encoding="utf-8")
old_source = subprocess.check_output(["git", "show", "6e5670f:Tinodios/MessageInteractor.swift"], cwd=ROOT).decode()
urls = (ROOT / "Tinodios/Utils.swift").read_text(encoding="utf-8")
anchor = '                guard let ctrl = serverMessage?.ctrl, ctrl.code == 200, let srvUrl = URL(string: ctrl.getStringParam(for: "url") ?? "") else {'
before, after = old_source.split(anchor)
old_body = re.findall(r"(?ms)^\s*case \.audio:\n(.*?)^\s*case \.file:", after)[0]
assert re.search(r"refurl: ref,", old_body), "Historical red callback lost"
# The old blob is preserved by AUDIO-REF-01. For this new captured-origin API,
# inject the same wrong-reference fault into the actual current consumer.
current_before, current_after = source.split(anchor)
wrong_reference = current_before + anchor + current_after.replace("draftyAudio(refurl: srvUrl,", "draftyAudio(refurl: ref,", 1)
work = ROOT / "build" / ("audio-ref-source-validation-" + uuid.uuid4().hex)
work.mkdir(parents=True)
assert work.resolve().is_relative_to((ROOT / "build").resolve())
results = []
for name, code, dirty, expected in [
    ("current-consumer-wrong-ref-red", wrong_reference, False, "Completed upload must use its server result"),
    ("current-green", source, False, None),
    ("duplicate-case-rejected", source.replace(anchor, anchor + "\ncase .audio:\n draft = nil\ncase .file:\n"), False, "Audio case is missing or ambiguous"),
    ("dirty-source-rejected", source, True, "Audio source differs from fixed HEAD blob"),
]:
    fixture = work / name
    (fixture / "Tinodios").mkdir(parents=True)
    (fixture / "Tinodios/MessageInteractor.swift").write_text(code, encoding="utf-8", newline="\n")
    (fixture / "Tinodios/Utils.swift").write_text(urls, encoding="utf-8", newline="\n")
    def git(*args):
        return subprocess.run(["git", *args], cwd=fixture, check=True, capture_output=True, text=True)
    git("init", "-q")
    git("config", "core.autocrlf", "false")
    git("add", "--", "Tinodios/MessageInteractor.swift", "Tinodios/Utils.swift")
    git("-c", "user.name=Source Fixture", "-c", "user.email=fixture@invalid", "commit", "-qm", "synthetic source snapshot")
    if dirty:
        with (fixture / "Tinodios/MessageInteractor.swift").open("a", encoding="utf-8") as f:
            f.write("\n// changed after frozen source snapshot\n")
    manifest = fixture / "static.json"
    manifest.write_text("{}", encoding="utf-8")
    result = subprocess.run([sys.executable, "-c", extractor, str(manifest)], cwd=fixture, text=True, capture_output=True)
    if expected is None:
        assert result.returncode == 0, result.stderr
        adapter = fixture / "build/ci-generated/AudioUploadConsumerFixture.swift"
        generated = adapter.read_bytes()
        out = ROOT / "build/ci-generated/AudioUploadConsumerFixture.swift"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(generated)
        outcome = json.loads(manifest.read_text())["audio_upload_source_adapter"]
    else:
        assert result.returncode != 0 and expected in result.stderr, (name, result.returncode, result.stderr)
        outcome = expected
    results.append({"case": name, "expected_failure": expected is not None, "exit": result.returncode, "outcome": outcome})
checks = {"scope": "Actual CI extractor executed against real safe source Git snapshots; not Swift/Drafty runtime",
          "production_delta": "captured original owner origin; historical legacy blob unchanged",
          "checks": results, "native_execution": "NOT_RUN; two methods prepared for later exact Mac CI"}
(REPORT / "audio-adapter-checks.json").write_text(json.dumps(checks, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"adapter_checks": len(results), "expected_red_and_rejection_cases": 3, "green": 1}))
