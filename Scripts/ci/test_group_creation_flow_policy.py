#!/usr/bin/env python3
"""Guard the premium two-step group creation flow."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "Tinodios" / "NewGroupViewController.swift").read_text(encoding="utf-8")


def main() -> None:
    for marker in [
        "private var hasPresentedMemberSelection = false",
        "presentMemberSelectionIfNeeded()",
        'performSegue(withIdentifier: "NewGroupToEditMembers"',
        "rebuildPremiumGroupDetails()",
        'NSLocalizedString("设置群资料"',
        'NSLocalizedString("创建群聊"',
        "membersSummaryLabel",
        "if premiumDetailsBuilt",
        "editMembersButtonTapped",
        'NSLocalizedString("请选择至少一位群成员"',
    ]:
        assert marker in SOURCE, f"missing premium group-flow marker: {marker}"

    premium_update = SOURCE.split("if premiumDetailsBuilt", 1)[1].split("completion(nil)", 1)[0]
    assert "beginUpdates()" not in premium_update
    assert "insertRows" not in premium_update
    assert "deleteRows" not in premium_update

    print("CLAW OS premium group creation flow checks passed.")


if __name__ == "__main__":
    main()
