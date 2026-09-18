#!/usr/bin/env python3
"""Guard CLAW OS iOS brand identity and shared UI design tokens."""

from pathlib import Path
import plistlib
import re
import struct


ROOT = Path(__file__).resolve().parents[2]
TINODIOS = ROOT / "Tinodios"
UTILS = TINODIOS / "Utils.swift"
APP_DELEGATE = TINODIOS / "AppDelegate.swift"
LOGIN = TINODIOS / "LoginViewController.swift"
SIGNUP = TINODIOS / "SignupViewController.swift"
CHAT_LIST = TINODIOS / "ChatListViewController.swift"
MESSAGE = TINODIOS / "MessageViewController.swift"
SEND_BAR = TINODIOS / "widgets" / "SendMessageBar.swift"
INFO = TINODIOS / "Info.plist"
STORYBOARD = TINODIOS / "Base.lproj" / "Main.storyboard"
MARKETING_ICON = (
    TINODIOS
    / "Supporting Files"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "AppIcon-ios-marketing-1024x1024-1x.png"
)


def png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"Not a PNG: {path}"
    assert data[12:16] == b"IHDR", f"Missing IHDR: {path}"
    return struct.unpack(">II", data[16:24])


def localized_values(path: Path) -> list[str]:
    values: list[str] = []
    assignment = re.compile(r'^\s*"(?:[^"\\]|\\.)*"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
    for line in path.read_text(encoding="utf-8").splitlines():
        match = assignment.match(line)
        if match:
            values.append(match.group(1))
    return values


def main() -> None:
    with INFO.open("rb") as stream:
        info = plistlib.load(stream)
    assert info["CFBundleDisplayName"] == "CLAW OS"
    assert info["CFBundleName"] == "CLAW OS"

    assert "APP_NAME = CLAW OS" in (ROOT / "prod.xcconfig").read_text(encoding="utf-8")
    assert "APP_NAME = CLAW OS (test)" in (ROOT / "devel.xcconfig").read_text(encoding="utf-8")
    assert png_dimensions(MARKETING_ICON) == (1024, 1024)

    forbidden = re.compile(r"\b(?:tinode|tindroid)\b", re.IGNORECASE)
    for strings_file in TINODIOS.glob("*.lproj/Main.strings"):
        leaked = [value for value in localized_values(strings_file) if forbidden.search(value)]
        assert not leaked, f"Visible legacy brand in {strings_file}: {leaked}"

    storyboard = STORYBOARD.read_text(encoding="utf-8")
    assert not re.search(
        r'(?:text|title|placeholder)="[^"]*\b(?:Tinode|Tindroid)\b[^"]*"',
        storyboard,
        re.IGNORECASE,
    )
    assert 'title="CLAW OS"' in storyboard

    utils = UTILS.read_text(encoding="utf-8")
    for marker in (
        "enum ClawTheme",
        "static let primary",
        "static let accent",
        "static let background",
        "static let surface",
        "static let border",
        "static let inputRadius: CGFloat = 14",
        "static let buttonRadius: CGFloat = 12",
        "static let cardRadius: CGFloat = 16",
        "static let touchTarget: CGFloat = 48",
        "static let iconSmall: CGFloat = 18",
        "static let iconCompact: CGFloat = 20",
        "static let iconStandard: CGFloat = 24",
        "static func applyGlobalAppearance()",
        "static func stylePrimaryButton",
        "static func styleTextField",
        "static func symbol(",
        "static func styleIconButton",
    ):
        assert marker in utils, f"Missing shared iOS design token: {marker}"

    app_delegate = APP_DELEGATE.read_text(encoding="utf-8")
    assert "ClawTheme.applyGlobalAppearance()" in app_delegate

    login = LOGIN.read_text(encoding="utf-8")
    assert 'ClawIdentityForm(title: "登录 CLAW OS"' in login
    assert 'UIImage(named: "logo-ios")' in login
    assert "view.backgroundColor = ClawTheme.background" in login
    assert "form.install(in: self)" in login
    signup = SIGNUP.read_text(encoding="utf-8")
    assert "SignupViewController: ClawIdentityEntryController" in signup
    assert "ClawTheme.styleTextField(field)" in utils
    assert "ClawTheme.stylePrimaryButton(button)" in utils
    assert "ClawTheme.font(16)" in utils

    chat_list = CHAT_LIST.read_text(encoding="utf-8")
    assert "Cache.tinode.getFilteredTopics" in chat_list
    assert "topic.topicType == .p2p" in chat_list
    assert "topic.isJoiner" in chat_list
    assert "for topic in allTopics where topic.isP2PType && !topic.deleted" not in chat_list
    assert "!topic.deleted" in chat_list
    assert "!Cache.tinode.isMe(uid: topic.name)" in chat_list
    assert "if lhs.inCall != rhs.inCall" in chat_list
    assert "if lhs.online != rhs.online" in chat_list
    assert "ActiveContactsLayoutMetrics.visibleCount" in chat_list
    assert "ActiveContactsLayoutMetrics.itemWidth" in chat_list
    assert "let avatarSize: CGFloat = 54" in chat_list
    assert "activeTopics.prefix" not in chat_list
    assert "min(activeTopics.count" not in chat_list
    assert "showAllContacts" in chat_list
    assert 'ClawTheme.symbol("magnifyingglass"' in chat_list
    assert "搜索会话" in chat_list

    message = MESSAGE.read_text(encoding="utf-8")
    assert 'ClawTheme.symbol("phone.fill"' in message
    assert 'buttonGoToLatest.setTitle("回到最新消息", for: .normal)' in message
    assert 'buttonGoToLatest.accessibilityLabel = "回到最新消息"' in message
    assert 'widthAnchor.constraint(greaterThanOrEqualToConstant: 44.0)' in message
    assert 'heightAnchor.constraint(greaterThanOrEqualToConstant: 44)' in message
    assert 'view.safeAreaLayoutGuide.leadingAnchor' in message
    assert 'adjustsFontForContentSizeCategory = true' in message
    assert 'title: "语音通话"' in message
    assert 'title: "视频通话"' in message

    send_bar = SEND_BAR.read_text(encoding="utf-8")
    assert "ClawAttachmentSheetController" in send_bar
    assert 'symbol: "photo.on.rectangle.angled"' in send_bar
    assert 'symbol: "camera"' in send_bar
    assert 'symbol: "doc"' in send_bar
    assert "widthAnchor.constraint(equalToConstant: 24)" in send_bar
    assert "heightAnchor.constraint(equalToConstant: 24)" in send_bar
    assert "panel.safeAreaLayoutGuide.bottomAnchor" in send_bar


if __name__ == "__main__":
    main()
