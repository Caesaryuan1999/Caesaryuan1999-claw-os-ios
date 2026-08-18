from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "Tinodios" / "AddByIDViewController.swift").read_text(encoding="utf-8")


assert "contentStack.alignment = .center" in SOURCE
assert "contentStack.spacing = 12" in SOURCE
assert "constraint.constant = 24" in SOURCE
assert "searchRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor)" in SOURCE
assert "idTextField.heightAnchor.constraint(equalToConstant: 48)" in SOURCE
assert "okayButton.widthAnchor.constraint(equalToConstant: 72)" in SOURCE
assert "showCodeButton.setTitle(NSLocalizedString(\"显示二维码\"" in SOURCE
assert "scanCodeButton.setTitle(NSLocalizedString(\"扫描二维码\"" in SOURCE
assert "let compactSide = min(252" in SOURCE
