#!/usr/bin/env python3
"""Guard call lifecycle behavior which previously caused random hangups."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "Tinodios" / "CallViewController.swift").read_text(encoding="utf-8")
MANAGER = (ROOT / "Tinodios" / "CallManager.swift").read_text(encoding="utf-8")
FIND_VIEW = (ROOT / "Tinodios" / "FindViewController.swift").read_text(encoding="utf-8")
MAIN_TABS = (ROOT / "Tinodios" / "NewChatTabController.swift").read_text(encoding="utf-8")


def main() -> None:
    for marker in [
        "private var isTerminatingCall = false",
        "private var didStopMedia = false",
        "private var didRemoveTinodeListener = false",
        "private var didSendInitialOffer = false",
        "private var didReceiveInitialOffer = false",
        "private var didMarkCallConnected = false",
        "isMovingFromParent || isBeingDismissed",
        "if isTerminalTransition && !isTerminatingCall",
        "guard !didStopMedia else { return }",
        "guard !isTerminatingCall else { return }",
        "guard !didRemoveTinodeListener, listener != nil else { return }",
        "guard !isTerminatingCall, callSeqId > 0, callDirection == .outgoing",
        "guard !didMarkCallConnected else { return }",
        "handleCallClose(notifyPeer: false)",
        "self.videoToggleButton.isEnabled = !self.isAudioOnlyCall",
    ]:
        assert marker in SOURCE, f"missing call lifecycle guard: {marker}"

    view_disappear = SOURCE.split("override func viewDidDisappear", 1)[1].split("@objc func handleRouteChange", 1)[0]
    assert "if isTerminatingCall" in view_disappear
    assert "stopMedia()" in view_disappear

    assert SOURCE.count("didSendInitialOffer = true") == 1
    assert SOURCE.count("didMarkCallConnected = true") == 1
    assert 'topic?.videoCall(event: "hang-up"' in SOURCE

    for marker in [
        "routeIncomingCallToApp",
        "系统来电界面不可用，已切换到应用内接听",
        "usesSystemCallUI",
        "messageVC.present(alert",
        "self?.handleOutgoingInviteFailure(err)",
        "private func handleOutgoingInviteFailure",
        "completeActiveCallFromApp",
        "callStatusLabel",
        'updateCallStatus("正在呼叫")',
        'updateCallStatus("等待对方接听")',
        'updateCallStatus("正在建立安全连接")',
        'updateCallStatus("已接通")',
        'updateCallStatus("通话失败")',
        'updateCallStatus("通话已结束")',
    ]:
        assert marker in SOURCE + MANAGER, f"missing call fallback marker: {marker}"

    for marker in [
        "isSelectingContactForCall",
        "presentCallTypePicker",
        "startCall(topicId: topicId, audioOnly:",
    ]:
        assert marker in FIND_VIEW, f"missing contact call picker marker: {marker}"
    assert "contacts.isSelectingContactForCall = true" in MAIN_TABS

    print("CLAW OS call lifecycle policy checks passed.")


if __name__ == "__main__":
    main()
