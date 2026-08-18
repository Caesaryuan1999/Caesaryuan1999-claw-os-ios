#!/usr/bin/env python3
"""Guard the iOS conversation-security rows against legacy icon/text drift."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TINODIOS = ROOT / "Tinodios"


def main() -> None:
    controller = (TINODIOS / "TopicSecurityViewController.swift").read_text(encoding="utf-8")
    storyboard = (TINODIOS / "Base.lproj" / "Main.storyboard").read_text(encoding="utf-8")
    scene = storyboard[storyboard.index('id="4vC-jn-jWQ"'):storyboard.index('id="b7f-OO-Sgt"')]

    for marker in (
        "tableView.separatorStyle = .none",
        "UIListContentConfiguration.valueCell()",
        "configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(",
        "configuration.imageProperties.reservedLayoutSize = CGSize(",
        "width: securityRowIconColumnWidth",
        "configuration.imageProperties.maximumSize = securityRowIconSize",
        "cell.contentConfiguration = configuration",
        "cell.imageView?.isHidden = true",
        "cell.textLabel?.isHidden = true",
        "cell.detailTextLabel?.isHidden = true",
    ):
        assert marker in controller, f"Missing security row layout marker: {marker}"

    assert 'ambiguous="YES"' not in scene
    print("iOS conversation-security layout policy checks passed.")


if __name__ == "__main__":
    main()
