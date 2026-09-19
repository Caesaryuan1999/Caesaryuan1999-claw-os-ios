from pathlib import Path
import hashlib, json, re, subprocess
ROOT = Path(__file__).resolve().parents[4]
SOURCE = "01d34caba9f73353e9fc60e350ae3484e7f5bbdd"
PATH = "TinodiosUITests/VoiceLayoutTests.swift"
old = subprocess.check_output(["git", "show", SOURCE + ":" + PATH], cwd=ROOT).decode("utf-8")
new = (ROOT / PATH).read_text(encoding="utf-8")
start = new.index("    func testOwnedAudioActualAACPlaybackPauseResumeAndFiniteSeek()")
end = new.index("    private func withCurrentTraits(", start)
rest = new[:start-1] + new[end:]  # Include only the new section's leading LF.
rest = rest[:rest.index("// Isolated real SDK/SQLite.")].rstrip() + "\n"
rest = rest.replace("import Network\n", "", 1).replace("@testable import TinodiosDB\n", "import TinodiosDB\n", 1)
assert rest == old
before = re.findall(r"    func (test\w+)\(", old)
after = re.findall(r"    func (test\w+)\(", new)
added = [name for name in after if name not in before]
assert len(before) == 11 and len(added) == 6 and len(after) == 17
fixture = new[new.index("private final class OrdinaryAudioHTTP"):]
assert fixture.index("listener.newConnectionHandler =") < fixture.index("listener.start(queue:")
assert "AVAudioPlayer(data: bytes)" in (ROOT / "Tinodios/MessageCell+VLCMediaPlayerDelegate.swift").read_text(encoding="utf-8")
production = [
    "Tinodios/MessageCell+VLCMediaPlayerDelegate.swift",
    "Tinodios/MessageCell.swift",
    "Tinodios/MessageViewController+MessageCellDelegate.swift",
    "Tinodios/MessageViewController.swift",
    "Tinodios/MessageViewController+SendMessageBarDelegate.swift",
]
for path in production:
    expected = subprocess.check_output(["git", "show", SOURCE + ":" + path], cwd=ROOT).decode("utf-8")
    assert (ROOT / path).read_text(encoding="utf-8") == expected
out = {
    "production_source": SOURCE, "test_path": PATH,
    "test_raw_sha256": hashlib.sha256((ROOT / PATH).read_bytes()).hexdigest(),
    "old_test_methods": before, "old_11_methods_and_helpers_exact_after_removing_new_sections": True,
    "new_test_methods": added, "total_voice_methods": len(after),
    "expected_native_not_run": 327, "expected_navigation_not_run": 3,
    "new_target_or_selector": False, "socket_handler_before_start": True,
    "production_unchanged_after_fixed_commit": True, "native_execution": "NOT_RUN",
    "evidence_level": "source boundary only; not Swift typechecking or network execution",
}
Path(__file__).with_name("test-source-checks.json").write_text(
    json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
print(json.dumps({"source_boundary": "PASS", "old_methods": 11, "added_methods": 6,
                  "voice_methods": 17, "native": "NOT_RUN"}, indent=2))
