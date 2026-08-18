#!/usr/bin/env python3
"""Guard the iOS contact-to-group and post-group interaction contract."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FIND_INTERACTOR = ROOT / "Tinodios" / "FindInteractor.swift"
FIND_VIEW = ROOT / "Tinodios" / "FindViewController.swift"
EDIT_MEMBERS = ROOT / "Tinodios" / "EditMembersViewController.swift"
CONTACTS_MANAGER = ROOT / "Tinodios" / "account" / "ContactsManager.swift"
NEW_GROUP = ROOT / "Tinodios" / "NewGroupViewController.swift"
TOPIC_INFO = ROOT / "Tinodios" / "TopicInfoViewController.swift"
TOPIC_SECURITY = ROOT / "Tinodios" / "TopicSecurityViewController.swift"
ZH_HANS = ROOT / "Tinodios" / "zh-Hans.lproj" / "Main.strings"


def main() -> None:
    find_interactor = FIND_INTERACTOR.read_text(encoding="utf-8")
    find_view = FIND_VIEW.read_text(encoding="utf-8")
    edit_members = EDIT_MEMBERS.read_text(encoding="utf-8")
    contacts_manager = CONTACTS_MANAGER.read_text(encoding="utf-8")
    new_group = NEW_GROUP.read_text(encoding="utf-8")
    topic_info = TOPIC_INFO.read_text(encoding="utf-8")
    topic_security = TOPIC_SECURITY.read_text(encoding="utf-8")
    zh_hans = ZH_HANS.read_text(encoding="utf-8")

    assert "completion: @escaping (Error?) -> Void" in find_interactor
    assert "topicUnwrapped.subscribe()" in find_interactor
    assert find_interactor.index("topicUnwrapped.subscribe()") < find_interactor.index("contactsManager.processSubscription")
    assert "isSavingRemoteContact" in find_view
    assert "guard let interactor = interactor else { return }" in find_view

    assert "UISearchController" in edit_members
    assert "filteredContacts" in edit_members
    assert "searchResultsUpdater" in edit_members
    assert "selectedContactIds" in edit_members
    assert "ContactsManager.isDirectContactId(uid)" in edit_members
    assert "Tinode.topicTypeByName(name: uid) == .p2p" in contacts_manager
    assert "ContactsManager.isDirectContactId(uniqueId)" in find_interactor

    assert "guard !isCreatingGroup else" in new_group
    assert "请选择至少一位群成员" in new_group
    assert "群聊已创建，部分成员添加失败，请在群设置中重试" in new_group
    assert "创建群聊 (%d)" in new_group

    assert "topic.isAdmin" in topic_info
    assert "topic.isOwner" in topic_info
    assert 'NSLocalizedString("Make owner"' in topic_info

    assert "guard topic.isOwner else" in topic_security
    assert "guard !topic.isOwner else" in topic_security
    assert "topic.delete(hard: true)" in topic_security
    assert "UIAlertController" in topic_security

    for key in (
        "Done",
        "Cancel",
        "Selected members (%d)",
        "Added to contacts",
        "Change permissions",
        "Make owner",
        "Remove",
        "Block",
    ):
        assert f'"{key}" =' in zh_hans, f"missing Simplified Chinese localization: {key}"


if __name__ == "__main__":
    main()
