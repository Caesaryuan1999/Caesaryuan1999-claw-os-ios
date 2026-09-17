#!/usr/bin/env python3
"""Prepare CocoaPods license XML without changing any XML-permitted source bytes."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import os


def prepare(source: Path, destination: Path, evidence_dir: Path) -> dict:
    original = source.read_bytes()
    # XML 1.0 permits TAB, LF and CR, but not the other C0 controls.
    # MobileVLCKit's LGPL text includes page-break FF bytes. Keep all visible text,
    # encoding, indentation, line endings and license entries byte-for-byte.
    removed = [(offset, value) for offset, value in enumerate(original)
               if value < 0x20 and value not in (0x09, 0x0A, 0x0D)]
    prepared = bytes(value for value in original
                     if value >= 0x20 or value in (0x09, 0x0A, 0x0D))
    evidence_dir.mkdir(parents=True, exist_ok=True)
    (evidence_dir / "original-acknowledgements.plist").write_bytes(original)
    manifest = {
        "transform": "remove XML-1.0-forbidden C0 bytes only; every other byte unchanged",
        "source_sha256": hashlib.sha256(original).hexdigest(),
        "prepared_sha256": hashlib.sha256(prepared).hexdigest(),
        "source_bytes": len(original), "prepared_bytes": len(prepared),
        "removed_count": len(removed),
        "removed_hex_counts": dict(Counter(f"{value:02x}" for _, value in removed)),
        "removed_offsets": [offset for offset, _ in removed],
    }
    manifest_path = evidence_dir / "license-manifest.json"
    try:
        if not prepared.lstrip().startswith((b"<?xml", b"<plist")):
            raise ValueError("Expected CocoaPods XML license plist")
        document = plistlib.loads(prepared)  # Reject any remaining XML/plist defect.
        entries = document.get("PreferenceSpecifiers") if isinstance(document, dict) else None
        if not isinstance(entries, list) or not entries:
            raise ValueError("License plist has no PreferenceSpecifiers")
        if not any(isinstance(item, dict) and item.get("Title") and item.get("FooterText") for item in entries):
            raise ValueError("License plist has no named license text")
    except Exception as error:
        manifest.update(strict_plist_parse="FAIL", error_type=type(error).__name__)
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        raise
    manifest.update(license_entry_count=len(entries),
                    license_titles=[item["Title"] for item in entries if isinstance(item, dict) and "Title" in item],
                    strict_plist_parse="PASS")
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".license-", delete=False) as stream:
            temporary = stream.name
            stream.write(prepared)
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)
    print(f"License XML: parsed {len(entries)} entries; removed {len(removed)} forbidden control bytes")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.source, args.destination, args.evidence_dir)

