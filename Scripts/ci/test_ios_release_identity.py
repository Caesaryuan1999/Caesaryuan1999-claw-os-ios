#!/usr/bin/env python3
"""Guard the IPA workflow against publishing an indistinguishable stale build."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "ios-ipa.yml"


def main() -> None:
    source = WORKFLOW.read_text(encoding="utf-8")

    assert "marketing_version:" in source, "IPA dispatch must expose a marketing version."
    assert "default: 1.0.1" in source, "The next test release must be version 1.0.1."
    assert "MARKETING_VERSION:" in source, "The workflow must define MARKETING_VERSION."
    assert 'MARKETING_VERSION="${MARKETING_VERSION}"' in source
    assert "CFBundleDisplayName" in source and "CLAW OS" in source
    assert "CFBundleIdentifier" in source and "${APP_BUNDLE_ID}" in source
    assert "CFBundleVersion" in source and "${BUILD_NUMBER}" in source
    assert "BUILD-IDENTITY.txt" in source
    assert "claw-os-ios-v${{ env.MARKETING_VERSION }}-build-${{ env.BUILD_NUMBER }}" in source


if __name__ == "__main__":
    main()
