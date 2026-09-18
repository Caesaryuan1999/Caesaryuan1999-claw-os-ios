"""Run the existing actual CI adapter checks; preserve the previous unit's report."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[4]
report = Path(__file__).resolve().parent
original = ROOT / "docs/handoff/R3/VOICE-LIFECYCLE-01/verify_audio_adapter.py"
code = original.read_text(encoding="utf-8")
anchor = "REPORT = Path(__file__).resolve().parent"
assert code.count(anchor) == 1
# Output routing only. All four real Git fixture cases and CI extraction stay original.
code = code.replace(anchor, "REPORT = ROOT / 'docs/handoff/R3/CHAT-SCROLL-01'")
exec(compile(code, str(original), "exec"), {"__file__": str(original), "__name__": "__main__"})
generated = (ROOT / "build/ci-generated/AudioUploadConsumerFixture.swift").read_text(encoding="utf-8")
assert "import Foundation" in generated and "import TinodeSDK" in generated
assert all(name not in generated for name in ["ChatDisplayIntent", "ChatDisplaySource", "MessagePresentationLogic", "submitRecordedAudio"])
shell = (ROOT / "Scripts/ci/verify_publish_outcomes_macos.sh").read_text(encoding="utf-8")
# The other generated UIKit fixture takes only the complete original reset/capture methods.
reset = re.search(r"(?ms)<<'VOICE_RESET_SOURCE'\n(.*?)^VOICE_RESET_SOURCE$", shell)[1]
assert "MessageInteractor.swift" not in reset and "MessageViewController.swift" not in reset
project = (ROOT / "Tinodios.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
assert project.count("fileRef = 0A0016E621E7236900088188") == 1
assert project.count("0A0016E721E7236900088188 /* MessageInteractor.swift in Sources */,") == 1
(report / "extractor-scope.json").write_text(json.dumps({
    "existingHarnessSHA256": hashlib.sha256(original.read_bytes()).hexdigest(),
    "generatedAudioSHA256": hashlib.sha256(generated.encode()).hexdigest(),
    "audio": "Actual current completion/initial cases + unchanged complete Drafty helper; four actual extractor Git cases",
    "reset": "Unchanged SendMessageBar capture/reset extractor; no new display types",
    "recorder": "Actual MediaRecorder source in unit target unchanged; does not depend on MessageInteractor",
    "localDelete": "Actual SDK/DB/ClawSecondaryUIState sources unchanged; no extraction of MessageInteractor",
    "fullInteractor": "Only App sources, compiled with MessageVC metadata; new ChatScrollTests imports App",
    "swiftExecution": "NOT_RUN Windows"
}, indent=2) + "\n", encoding="utf-8")
