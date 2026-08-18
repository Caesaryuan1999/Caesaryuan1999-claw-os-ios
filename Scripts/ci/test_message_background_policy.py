from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MESSAGE_VIEW = (ROOT / "Tinodios" / "MessageView.swift").read_text(encoding="utf-8")
MESSAGE_CELL = (ROOT / "Tinodios" / "MessageCell.swift").read_text(encoding="utf-8")
SEND_BAR = (ROOT / "Tinodios" / "widgets" / "SendMessageBar.swift").read_text(encoding="utf-8")
SEND_BAR_XIB = (ROOT / "Tinodios" / "widgets" / "SendMessageBar.xib").read_text(encoding="utf-8")


assert "backgroundColor = ClawTheme.background" in MESSAGE_VIEW
assert "backgroundColor = .white" not in MESSAGE_VIEW
assert "backgroundColor = .black" not in MESSAGE_VIEW
assert "func applyThemeBackground()" in MESSAGE_CELL
assert "contentView.backgroundColor = .clear" in MESSAGE_CELL
assert "inputField.placeholderText = NSLocalizedString(\"请输入\"" in SEND_BAR
assert 'keyPath="placeholderText" value="请输入"' in SEND_BAR_XIB
