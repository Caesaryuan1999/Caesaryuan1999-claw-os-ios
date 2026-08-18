"""Static guardrails for CLAW OS contacts, groups, calls and settings UI."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TINODIOS = ROOT / "Tinodios"


def source(name: str) -> str:
    return (TINODIOS / name).read_text(encoding="utf-8")


theme = source("Utils.swift")
contacts = source("FindViewController.swift")
members = source("EditMembersViewController.swift")
group = source("NewGroupViewController.swift")
call = source("CallViewController.swift")
account = source("AccountSettingsViewController.swift")
topic_info = source("TopicInfoViewController.swift")
topic_general = source("TopicGeneralViewController.swift")
topic_security = source("TopicSecurityViewController.swift")

for marker in ["styleSearchBar", "styleList", "styleCard", "styleCallControl"]:
    assert marker in theme, f"missing shared CLAW OS UI primitive: {marker}"

assert "ClawTheme.styleSearchBar(searchController.searchBar)" in contacts
assert "ClawTheme.styleList(tableView, rowHeight: 76)" in contacts
for marker in [
    "ClawContactsHeaderView",
    "ClawActiveContactCell",
    "UICollectionViewDelegateFlowLayout",
    "ActiveContactsLayoutMetrics.itemWidth",
    "static var height: CGFloat { 98 + ActiveContactsLayoutMetrics.stripHeight }",
    "发起群聊",
    "查找联系人",
    "邀请朋友",
]:
    assert marker in contacts, f"missing premium contacts behavior: {marker}"
for marker in [
    "claw.contacts.screen",
    "claw.contacts.list",
    "claw.contacts.search",
    "claw.contacts.add",
]:
    assert marker in contacts, f"missing contacts automation identifier: {marker}"

assert "ClawTheme.styleList(membersTableView, rowHeight: 70)" in members
for marker in [
    "claw.group.members.screen",
    "claw.group.members.list",
    "claw.group.members.selected",
    "claw.group.members.search",
    "claw.group.members.done",
    "claw.group.members.cancel",
]:
    assert marker in members, f"missing member-selection automation identifier: {marker}"

assert "ClawTheme.styleList(tableView, rowHeight: 70)" in group
assert "return indexPath.section == 0 || indexPath.row == 0 ? super.tableView" in group
assert ": 70" in group, "group member rows must match Figma node 27:6"
for marker in [
    "claw.group.create.screen",
    "claw.group.create.form",
    "claw.group.create.name",
    "claw.group.create.private",
    "claw.group.create.tags",
    "claw.group.create.avatar",
    "claw.group.create.channel",
    "claw.group.create.submit",
]:
    assert marker in group, f"missing group-creation automation identifier: {marker}"

assert 'UIImage(named: "vc' not in call, "legacy call bitmap icons must not be used"
assert "imageEdgeInsets = UIEdgeInsets" not in call, "call icons must not use hand-tuned offsets"
assert "addBlurEffect()" not in call, "call controls must remain crisp"
for symbol_name in ["video.fill", "video.slash.fill", "mic.fill", "speaker.wave.2.fill", "phone.down.fill"]:
    assert symbol_name in call, f"missing centered SF Symbol: {symbol_name}"
for marker in [
    "claw.call.screen",
    "claw.call.speaker",
    "claw.call.microphone",
    "claw.call.video",
    "claw.call.hangup",
    "claw.call.peer-name",
    "claw.call.peer-avatar",
]:
    assert marker in call, f"missing call automation identifier: {marker}"

assert "ClawTheme.styleList(tableView, rowHeight: 72)" in account
for marker in [
    "ClawTheme.styleCard(settingsCard)",
    "premiumAvatar.heightAnchor.constraint(equalToConstant: 112)",
    "logoutButton.heightAnchor.constraint(equalToConstant: 54)",
    "AccountSettings2General",
    "AccountSettings2Notifications",
    "AccountSettings2Security",
    "tableView.tableFooterView = UIView(frame: .zero)",
]:
    assert marker in account, f"missing Figma account-settings structure: {marker}"
assert "makeDeviceInfoFooter" not in account, "phone information belongs in Security, not the account home"
for marker in ["claw.settings.account.screen", "claw.settings.account.list"]:
    assert marker in account, f"missing account-settings automation identifier: {marker}"

assert "ClawTheme.styleList(tableView, rowHeight: 64)" in topic_info
for marker in ["claw.settings.topic.info.screen", "claw.settings.topic.info.list"]:
    assert marker in topic_info, f"missing topic-info automation identifier: {marker}"

for marker in [
    "claw.settings.topic.general.screen",
    "claw.settings.topic.general.list",
    "claw.settings.topic.general.avatar",
]:
    assert marker in topic_general, f"missing topic-general automation identifier: {marker}"

assert 'ClawTheme.styleTableCell(actionDeleteMessages, symbolName: "trash", destructive: true)' in topic_security
assert "ClawTheme.styleGroupedCell(" in topic_security
assert "destructive: isDanger" in topic_security
for marker in [
    "claw.settings.topic.security.screen",
    "claw.settings.topic.security.list",
    "claw.settings.topic.security.delete-messages",
    "claw.settings.topic.security.delete-group",
    "claw.settings.topic.security.leave-group",
    "claw.settings.topic.security.leave-conversation",
]:
    assert marker in topic_security, f"missing topic-security automation identifier: {marker}"

print("CLAW OS secondary UI policy checks passed.")
