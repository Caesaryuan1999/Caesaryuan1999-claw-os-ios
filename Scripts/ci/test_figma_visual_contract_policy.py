#!/usr/bin/env python3
"""Guard the high-visibility CLAW OS Figma visual contract."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TINODIOS = ROOT / "Tinodios"


def read(relative: str) -> str:
    return (TINODIOS / relative).read_text(encoding="utf-8")


theme = read("Utils.swift")
messages = read("MessageViewController.swift")
bubbles = read("MessageBubbleDecorator.swift")
send_bar = read("widgets/SendMessageBar.swift")
simplified = read("zh-Hans.lproj/Main.strings")
traditional = read("zh-Hant.lproj/Main.strings")
members = read("EditMembersViewController.swift")

for marker in [
    "color(light: 0x006F64, dark: 0x72D9BF)",
    "color(light: 0xF4F6F3, dark: 0x101B19)",
    "static let inputRadius: CGFloat = 14",
    "static let buttonRadius: CGFloat = 12",
    "static let iconStandard: CGFloat = 24",
]:
    assert marker in theme, f"missing Figma design token: {marker}"

for marker in [
    "kOutgoingBubbleColorLight = ClawTheme.primary",
    "kOutgoingTextColorLight = UIColor.white",
    "kIncomingBubbleColorLight = ClawTheme.surfaceMuted",
    "kIncomingTextColorLight = ClawTheme.ink",
]:
    assert marker in messages, f"missing Figma message color contract: {marker}"
assert "UIBezierPath(roundedRect: rect, cornerRadius: 18)" in bubbles
assert "drawIncoming" not in bubbles and "drawOutgoing" not in bubbles

for marker in [
    "ClawAttachmentSheetController",
    "panel.layer.cornerRadius = 20",
    "actions.distribution = .fillEqually",
    "actions.spacing = 12",
    "iconFrame.widthAnchor.constraint(equalToConstant: 56)",
    "icon.widthAnchor.constraint(equalToConstant: 24)",
    "icon.contentMode = .scaleAspectFit",
]:
    assert marker in send_bar, f"missing centered attachment component: {marker}"

for key in [
    "Send content",
    "Choose photo or video",
    "Take photo or video",
    "File",
    "Camera is not available",
]:
    assert f'"{key}" =' in simplified, f"missing Simplified Chinese localization: {key}"
    assert f'"{key}" =' in traditional, f"missing Traditional Chinese localization: {key}"

for label in ["创建群聊", "管理成员", "已选择 %d 人", "下一步（%d）", "保存（%d）"]:
    assert label in members, f"missing Chinese group interaction label: {label}"

print("CLAW OS Figma visual contract checks passed.")
