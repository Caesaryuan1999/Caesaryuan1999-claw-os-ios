#!/usr/bin/env python3
"""Guard the iOS security settings row layout against legacy icon overflow."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SECURITY = ROOT / "Tinodios" / "SettingsSecurityViewController.swift"


def main() -> None:
    source = SECURITY.read_text(encoding="utf-8")

    required_markers = [
        "UIListContentConfiguration.valueCell()",
        "configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(",
        "leading: securityRowLeadingInset",
        "trailing: securityRowTrailingInset",
        "configuration.imageProperties.reservedLayoutSize = securityRowIconColumnWidth",
        "private let securityRowIconSize = CGSize(width: 28, height: 28)",
        "cell.contentConfiguration = configuration",
        "cell.imageView?.isHidden = true",
    ]
    for marker in required_markers:
        assert marker in source, f"Missing security row layout marker: {marker}"

    forbidden_markers = [
        'ClawTheme.styleTableCell(authUsersPermissions, symbolName:',
        'ClawTheme.styleTableCell(anonUsersPermissions, symbolName:',
        'ClawTheme.styleTableCell(actionChangePassword, symbolName:',
        'ClawTheme.styleTableCell(actionBlockedContacts, symbolName:',
        'ClawTheme.styleTableCell(actionDeleteAccount, symbolName:',
    ]
    for marker in forbidden_markers:
        assert marker not in source, f"Security rows must not use legacy imageView layout: {marker}"


if __name__ == "__main__":
    main()
