#!/usr/bin/env python3
"""Guard the iOS user-settings screen title, separators and static-cell layout."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TINODIOS = ROOT / "Tinodios"


def main() -> None:
    controller = (TINODIOS / "TopicInfoViewController.swift").read_text(encoding="utf-8")
    theme = (TINODIOS / "Utils.swift").read_text(encoding="utf-8")
    storyboard = (TINODIOS / "Base.lproj" / "Main.storyboard").read_text(encoding="utf-8")
    scene = storyboard[storyboard.index('id="ZxW-bT-ZdQ"'):storyboard.index('id="2Ct-oM-2pn"')]

    assert 'NSLocalizedString("聊天信息"' in controller
    assert "tableView.separatorStyle = .none" in controller
    assert "imageView?.preferredSymbolConfiguration" in controller
    assert 'ambiguous="YES"' not in scene
    assert "fillView.frame = bounds.inset(by: UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18))" in theme

    print("iOS user-settings layout policy checks passed.")


if __name__ == "__main__":
    main()
