from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BASE = "abc23071b23671323d7bce89340ea6ffb513cb3b"
checks = []


def check(name, condition):
    checks.append({"name": name, "pass": bool(condition)})
    assert condition, name


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def old(path):
    return subprocess.check_output(["git", "show", BASE + ":" + path], cwd=ROOT).decode("utf-8").replace("\r\n", "\n")


def methods(text):
    result = {}
    for match in re.finditer(r"    func (test\w+)\([^\n]*\{", text):
        start = match.start()
        end = match.end()
        depth = 1
        while depth:
            depth += (text[end] == "{") - (text[end] == "}")
            end += 1
        result[match.group(1)] = text[start:end]
    return result


def selected_methods(text, name):
    blocks = re.findall(r"(?ms)^(?:(?:final )?class|extension) " + re.escape(name)
                        + r"\b[^\n]*\{\n.*?^\}", text)
    result = {}
    for block in blocks:
        result.update(methods(block))
    return result


helper = read("Tinodios/ClawSecondaryUIState.swift")
video = read("Tinodios/VideoPreviewController.swift")
check("source red: remote query handed to VLC", "addAuthQueryParams(mediaURL)" in old("Tinodios/VideoPreviewController.swift"))
check("remote auth URL no longer handed to VLC", "addAuthQueryParams" not in video)
check("owned complete callback precedes local VLC entry", "self.beginPlayback(VLCMedia(url: file), ownedFile: file, source: source)" in video)
check("only bounded current original context downloads", "budget: playbackBudget" in video and "self.acceptsSource(source)" in video)
check("separate play/share transfer responsibilities", "private var playbackDownload:" in video and "private var download:" in video)
check("negotiated limit and default stay captured", "context.owner.getServerLimit(for: Tinode.kMaxFileUploadSize, withDefault: 8 * 1024 * 1024)" in helper)
check("overflow checked copies and reserve", "multipliedReportingOverflow(by: 2)" in helper and "addingReportingOverflow(Self.reserveBytes)" in helper and "16 * 1024 * 1024" in helper)
check("actual free space and preflight", "attributesOfFileSystem(forPath: root.path)" in helper and "try budget?.preflight(at: root)" in helper)
check("progress includes unknown-length written bytes", "try budget?.checkProgress(written: totalBytesWritten, expected: totalBytesExpectedToWrite)" in helper)
check("both temporary and final file rechecked", "try budget?.checkFile(location)" in helper and "try budget?.checkFile(export)" in helper)
check("nonvideo budget default preserves compatibility", "budget: ClawVideoDownloadBudget? = nil" in helper)
check("no shared cookie/cache/redirect relaxation", "config.urlCache = nil" in helper and "config.httpCookieStorage = nil" in helper and "completionHandler(nil)" in helper)
check("fixed visible common timer", "Timer(timeInterval: 0.25, repeats: true)" in video and "self.previewVisible" in video and "RunLoop.main.add(timer, forMode: .common)" in video)
check("timers canceled on page closure", "ownerTimer?.invalidate()" in video and "playbackDownload?.cancel()" in video)
check("same-attempt player closures", "let currentPlayer = VLCMediaPlayer()" in video and "stop: { currentPlayer.stop() }" in video and "player === self.player" in video)
check("actual lease used before play", "if !lease.play({ currentPlayer.play() })" in video)
check("stop requires actual event and state", "self.retired, self.isStopped()" in helper and "(!requestedPlay || observedStopped), isStopped()" in helper)
check("timeout retains attempt without unlink", "self.cleanupPending = !self.cleaned" in helper and "Self.pending[identity] = self" in helper)
check("stop event observes exact player", 'object: player, queue: .main' in helper)
check("local caller-owned URL has no deletion lease", "beginPlayback(VLCMedia(url: videoURL), ownedFile: nil" in video)
check("inline source unchanged", "VLCMedia(stream: InputStream(data: bits))" in video)
send_marker = "extension VideoPreviewController: SendImageBarDelegate"
check("send attachment method unchanged", video.split(send_marker, 1)[1] == old("Tinodios/VideoPreviewController.swift").split(send_marker, 1)[1])
check("Figma preparing copy", "视频下载完成后即可播放。返回聊天将取消本次加载。" in video and "取消并返回" in video)
check("distinct reason recovery", "当前账号无权查看这段视频。" in video and "case .tooLarge, .insufficientSpace, .spaceUnavailable" in video and "case .network:" in video)
check("valid source decode failure keeps share", "你可以返回聊天后重新打开，或分享原文件。" in video)

native = []
for path, expected, added in [("TinodiosUITests/OwnedImageTests.swift", 29, 8),
                              ("TinodiosUITests/VLCPlaybackProbeTests.swift", 7, 3)]:
    name = Path(path).stem
    previous, current = selected_methods(old(path), name), selected_methods(read(path), name)
    check(path + " every method belongs to selected XCTest class", len(current) == len(methods(read(path))))
    check(path + " all old test bodies identical", all(current.get(name) == body for name, body in previous.items()))
    check(path + " exact method count", len(current) == expected and len(current) - len(previous) == added)
    native.append({"file": path, "totalMethods": len(current), "newMethods": sorted(set(current) - set(previous)),
                   "sha256": hashlib.sha256((ROOT / path).read_bytes()).hexdigest()})
probe = read("TinodiosUITests/VLCPlaybackProbeTests.swift")
check("real helper real VLC tests", "ClawOwnedFileDownload(context:" in probe and "ClawOwnedPlaybackLease(context:" in probe and "playback.player.state == .paused" in probe)
check("playlist observed separately not security assertion", "CONFIRMED_SECONDARY_NETWORK_ACCESS" in probe and "NOT_OBSERVED_NOT_NETWORK_ISOLATION_PROOF" in probe)
check("existing class selectors cover all additions", all(s in read("Scripts/ci/verify_publish_outcomes_macos.sh") for s in ["-only-testing:TinodiosUITests/OwnedImageTests", "-only-testing:TinodiosVLCProbeTests/VLCPlaybackProbeTests"]))

output = {"level": "Windows source checks only; not Swift execution", "base": BASE,
          "checks": checks, "nativeInventory": native,
          "expected": {"sdk": 44, "uiRunner": 175, "vlcHost": 7, "totalNative": 226, "navigationSeparate": 3}}
(Path(__file__).parent / "source-checks.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
print(f"VIDEO-OWNED-02 source checks {len(checks)}/{len(checks)}; 226 + navigation3 EXPECTED, NOT_RUN")
