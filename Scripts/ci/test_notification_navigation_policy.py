#!/usr/bin/env python3
"""Guard notification settings navigation against static/dynamic table crashes."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ACCOUNT = ROOT / "Tinodios" / "AccountSettingsViewController.swift"
SETTINGS = ROOT / "Tinodios" / "SettingsNotificationsViewController.swift"


def main() -> None:
    account = ACCOUNT.read_text(encoding="utf-8")
    settings = SETTINGS.read_text(encoding="utf-8")

    assert "SettingsNotificationsViewController(style: .insetGrouped)" in account
    assert "navigationController.pushViewController(notifications, animated: true)" in account
    assert "performSegue(withIdentifier: \"AccountSettings2Notifications\"" not in account

    assert "tableView = premiumTable" not in settings
    assert "tableView.dataSource = self" in settings
    assert "tableView.delegate = self" in settings


if __name__ == "__main__":
    main()
