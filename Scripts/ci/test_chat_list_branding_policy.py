#!/usr/bin/env python3
"""Guard the iOS chat-list brand header and CLAW file assistant identity."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TINODIOS = ROOT / "Tinodios"


def main() -> None:
    chat_list = (TINODIOS / "ChatListViewController.swift").read_text(encoding="utf-8")
    chat_cell = (TINODIOS / "widgets" / "ChatListViewCell.swift").read_text(encoding="utf-8")
    avatar = (TINODIOS / "widgets" / "AvatarWithOnlineIndicator.swift").read_text(encoding="utf-8")
    round_image = (TINODIOS / "widgets" / "RoundImageView.swift").read_text(encoding="utf-8")

    assert "navigationItem.title = nil" in chat_list
    assert 'title.text = "CLAW OS"' in chat_list
    assert "navigationItem.leftBarButtonItem" in chat_list

    assert 'NSLocalizedString("CLAW文件助手"' in chat_cell
    assert "icon.setBrandingIcon()" in chat_cell
    assert "avatar.setBrandingIcon()" in avatar
    assert 'UIImage(named: "logo-ios")' in round_image
    assert "contentMode = .scaleAspectFill" in round_image
    assert "setFixedCornerRadius(16)" in chat_cell

    for relative in (
        "FindViewController.swift",
        "MessageViewController+MessageDisplayLogic.swift",
        "TopicInfoViewController.swift",
        "TopicGeneralViewController.swift",
    ):
        source = (TINODIOS / relative).read_text(encoding="utf-8")
        assert 'NSLocalizedString("CLAW文件助手"' in source, f"missing assistant title in {relative}"

    print("iOS chat-list branding policy checks passed.")


if __name__ == "__main__":
    main()
