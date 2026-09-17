#!/usr/bin/env python3
"""Execute the same license preparation called by CocoaPods post_install."""
from pathlib import Path
import contextlib
import io
import plistlib
import tempfile
import unittest

from prepare_license_plist import prepare


class LicensePlistTests(unittest.TestCase):
    def run_prepare(self, original: bytes):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        source, destination = root / "source.plist", root / "destination.plist"
        source.write_bytes(original)
        with contextlib.redirect_stdout(io.StringIO()):
            manifest = prepare(source, destination, root / "evidence")
        self.assertEqual((root / "evidence/original-acknowledgements.plist").read_bytes(), original)
        return destination.read_bytes(), manifest

    def fixture(self, text="Visible license & original copyright\nnext line\tend"):
        return plistlib.dumps({"PreferenceSpecifiers": [{"Title": "Synthetic license", "FooterText": text}]})

    def test_valid_xml_is_byte_identical(self):
        original = self.fixture()
        result, manifest = self.run_prepare(original)
        self.assertEqual(result, original)
        self.assertEqual(manifest["removed_count"], 0)

    def test_only_invalid_c0_controls_removed_visible_bytes_preserved(self):
        valid = self.fixture()
        controls = bytes(value for value in range(32) if value not in (9, 10, 13))
        original = valid.replace(b"next line", controls + b"next line")
        result, manifest = self.run_prepare(original)
        self.assertEqual(result, valid)
        self.assertEqual(manifest["removed_count"], len(controls))
        self.assertEqual(plistlib.loads(result)["PreferenceSpecifiers"][0]["FooterText"],
                         "Visible license & original copyright\nnext line\tend")

    def test_malformed_xml_does_not_replace_existing_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, destination = root / "source.plist", root / "destination.plist"
            source.write_bytes(b"<plist><dict>\x0cbroken")
            destination.write_bytes(b"retained existing file")
            with self.assertRaises(Exception):
                prepare(source, destination, root / "evidence")
            self.assertEqual(destination.read_bytes(), b"retained existing file")

    def test_non_c0_encoding_error_is_not_sanitized_or_installed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, destination = root / "source.plist", root / "destination.plist"
            original = self.fixture().replace(b"next line", b"bad" + bytes([255]) + b"encoding")
            source.write_bytes(original)
            destination.write_bytes(b"retain")
            with self.assertRaises(Exception):
                prepare(source, destination, root / "evidence")
            self.assertEqual(destination.read_bytes(), b"retain")
            self.assertEqual((root / "evidence/original-acknowledgements.plist").read_bytes(), original)

    def test_empty_license_list_is_rejected(self):
        with self.assertRaises(ValueError):
            self.run_prepare(plistlib.dumps({"PreferenceSpecifiers": []}))

    def test_actual_resource_has_all_license_entries_and_lgpl_text(self):
        actual = Path(__file__).resolve().parents[2] / "Tinodios/Settings.bundle/Acknowledgements.plist"
        result, manifest = self.run_prepare(actual.read_bytes())
        document = plistlib.loads(result)
        vlc = next(item for item in document["PreferenceSpecifiers"] if item.get("Title") == "MobileVLCKit")
        self.assertIn("GNU LESSER GENERAL PUBLIC LICENSE", vlc["FooterText"])
        self.assertIn("END OF TERMS AND CONDITIONS", vlc["FooterText"])
        self.assertGreaterEqual(manifest["license_entry_count"], 25)


if __name__ == "__main__":
    unittest.main()

