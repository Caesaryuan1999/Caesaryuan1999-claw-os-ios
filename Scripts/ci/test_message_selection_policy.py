"""Guard Android-parity multi-select actions in the iOS message screen."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def source(name: str) -> str:
    return (ROOT / "Tinodios" / name).read_text(encoding="utf-8")


message_view = source("MessageView.swift")
message_cell = source("MessageCell.swift")
message_controller = source("MessageViewController.swift")
message_actions = source("MessageViewController+MessageCellDelegate.swift")

assert "isBulkSelectionMode" in message_view
assert "setBulkSelection" in message_cell
assert "beginBulkMessageSelection" in message_controller
assert "collectionView.cellDelegate = self" in message_controller
assert "finishBulkMessageSelection" in message_controller
assert "toggleBulkMessageSelection" in message_actions
assert 'NSLocalizedString("多选"' in message_actions
assert 'NSLocalizedString("重试发送"' in message_actions
assert 'NSLocalizedString("删除所选消息"' in message_actions

print("iOS message multi-select policy checks passed")
