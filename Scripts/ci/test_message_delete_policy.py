#!/usr/bin/env python3
"""Guard CLAW OS iOS message deletion rollback and summary-refresh contracts."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INTERACTOR = ROOT / "Tinodios" / "MessageInteractor.swift"
TOPIC_SECURITY = ROOT / "Tinodios" / "TopicSecurityViewController.swift"
TOPIC = ROOT / "TinodeSDK" / "Topic.swift"
MENU = ROOT / "Tinodios" / "MessageViewController+MessageCellDelegate.swift"
MESSAGE_VIEW = ROOT / "Tinodios" / "MessageViewController.swift"
FORMAT_NODE = ROOT / "Tinodios" / "format" / "FormatNode.swift"


def main() -> None:
    interactor = INTERACTOR.read_text(encoding="utf-8")
    topic_security = TOPIC_SECURITY.read_text(encoding="utf-8")
    topic = TOPIC.read_text(encoding="utf-8")
    menu = MENU.read_text(encoding="utf-8")
    message_view = MESSAGE_VIEW.read_text(encoding="utf-8")
    format_node = FORMAT_NODE.read_text(encoding="utf-8")

    delete_block = interactor.split("func deleteMessage(_ message: Message, hard: Bool) {", 1)[1]
    delete_block = delete_block.split("private func commitLocalDeletes", 1)[0]
    remote_call = delete_block.index("topic.delMessages(ids: uniqueSeqIds, hard: hard)")
    success_branch = delete_block.index("onSuccess:", remote_call)
    failure_branch = delete_block.index("onFailure:", success_branch)

    assert "func commitLocalDeletes" in interactor
    assert "store.msgDiscard" not in delete_block[:remote_call]
    assert "commitLocalDeletes" in delete_block[success_branch:failure_branch]
    assert "commitLocalDeletes" not in delete_block[failure_branch:]
    assert "presentMessages(messages: visibleMessages" in delete_block

    assert "private var isDeletingMessages = false" in topic_security
    assert "guard !self.isDeletingMessages else" in topic_security
    assert topic_security.count("isDeletingMessages = false") >= 2

    assert "refreshLatestMessageFromStore" in topic
    assert "latestMessageValue = nil" in topic
    assert topic.count("refreshLatestMessageFromStore()") >= 4

    assert 'NSLocalizedString("删除该消息"' in menu
    assert 'NSLocalizedString("为所有人删除"' in menu
    assert "let messageSeqId = cell.seqId" in menu
    assert "deleteMessage(seqId: messageSeqId" in menu
    assert "backgroundTapped" in menu
    assert "dismiss(animated: true)" in menu
    assert "enum MessageBubbleLayoutPolicy" in message_view
    assert "maxContentWidth(availableWidth:" in message_view
    assert "voiceWidth(durationMs:" in message_view
    assert "MessageBubbleLayoutPolicy.voiceWidth" in format_node


if __name__ == "__main__":
    main()
