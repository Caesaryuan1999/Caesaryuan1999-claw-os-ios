#!/usr/bin/env python3
"""Guard the account device-info popup and its privacy boundary."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ACCOUNT_SETTINGS = ROOT / "Tinodios" / "AccountSettingsViewController.swift"
LOCALIZATIONS = [
    ROOT / "en.lproj" / "Localizable.strings",
    ROOT / "zh-Hans.lproj" / "Localizable.strings",
    ROOT / "zh-Hant.lproj" / "Localizable.strings",
]


def main() -> None:
    source = ACCOUNT_SETTINGS.read_text(encoding="utf-8")

    required_source = [
        "showDeviceInfo",
        "makeDeviceInfoFooter",
        "UIDevice.current.model",
        "systemVersion",
        "CFBundleShortVersionString",
        "Locale.preferredLanguages",
        "UIPasteboard.general.string",
    ]
    for marker in required_source:
        assert marker in source, f"Missing device-info implementation marker: {marker}"

    forbidden_source = [
        "identifierForVendor",
        "serialNumber",
        "IMEI",
        "mobileSubscriber",
        "CTTelephonyNetworkInfo",
    ]
    for marker in forbidden_source:
        assert marker not in source, f"Device info must not read sensitive identifier: {marker}"

    required_keys = [
        '"device_info"',
        '"device_info_explained"',
        '"device_model"',
        '"operating_system"',
        '"app_version"',
        '"current_language"',
        '"copy_info"',
        '"privacy_device_info"',
    ]
    for localization in LOCALIZATIONS:
        content = localization.read_text(encoding="utf-8")
        for key in required_keys:
            assert key in content, f"{localization.name} is missing {key}"


if __name__ == "__main__":
    main()
