#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CHAT_LIST = (ROOT / "Tinodios" / "ChatListViewController.swift").read_text(encoding="utf-8")
CONTACTS = (ROOT / "Tinodios" / "FindViewController.swift").read_text(encoding="utf-8")
UI_UTILS = (ROOT / "Tinodios" / "UiUtils.swift").read_text(encoding="utf-8")


def visible_count(width: int, inset: int, spacing: int, minimum_item_width: int) -> int:
    usable = width - inset * 2
    required_for_six = minimum_item_width * 6 + spacing * 5
    required_for_five = minimum_item_width * 5 + spacing * 4
    required_for_four = minimum_item_width * 4 + spacing * 3
    if usable >= required_for_six:
        return 6
    if usable >= required_for_five:
        return 5
    if usable >= required_for_four:
        return 4
    return 3


def item_width(width: int, inset: int, spacing: int, minimum_item_width: int) -> int:
    count = visible_count(width, inset, spacing, minimum_item_width)
    return (width - inset * 2 - spacing * (count - 1)) // count


def main() -> None:
    assert "enum ActiveContactsLayoutMetrics" in UI_UTILS
    assert "ActiveContactsLayoutMetrics.itemWidth" in CHAT_LIST
    assert "ActiveContactsLayoutMetrics.contentWidth" in CHAT_LIST
    assert "ActiveContactsLayoutMetrics.stripHeight" in CHAT_LIST
    assert "static let baseStripHeight: CGFloat = 164" in UI_UTILS
    assert "static var stripHeight: CGFloat" in UI_UTILS
    assert "static var scaledMinimumItemWidth" in UI_UTILS
    assert "let hasActiveContacts = false" in CHAT_LIST
    assert "activeContactItems = buildActiveContactItems()" in CHAT_LIST
    assert "let headerHeight: CGFloat = searchHeight + 24" in CHAT_LIST
    # R4 hides the chat strip at presentation only; original metrics/data remain covered.
    assert "ClawActiveContactCell" not in CONTACTS
    assert "premiumHeader.onAddContact" in CONTACTS
    assert "premiumHeader.onCreateGroup" in CONTACTS
    assert "ClawProfileLayout.fitHeader(in: tableView)" in CONTACTS
    assert "searchBar.searchTextField.attributedPlaceholder" in CONTACTS
    assert "searchBar.textField" not in CONTACTS
    assert "name.numberOfLines = 2" in CHAT_LIST
    assert "floor(availableWidth / 5)" not in CONTACTS

    wide_width = item_width(430, 16, 8, 82)
    assert visible_count(430, 16, 8, 82) == 4
    assert wide_width * 4 + 8 * 3 + 16 * 2 <= 430

    narrow_width = item_width(320, 16, 8, 82)
    assert visible_count(320, 16, 8, 82) == 3
    assert narrow_width >= 82
    assert narrow_width * 3 + 8 * 2 + 16 * 2 <= 320

    compact_width = item_width(280, 16, 8, 82)
    assert visible_count(280, 16, 8, 82) == 3
    assert compact_width > 0
    assert compact_width * 3 + 8 * 2 + 16 * 2 <= 280

    tablet_width = item_width(768, 20, 8, 82)
    assert visible_count(768, 20, 8, 82) == 6
    assert tablet_width * 6 + 8 * 5 + 20 * 2 <= 768


if __name__ == "__main__":
    main()
