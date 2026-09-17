"""Production smoke runner with controlled macOS command boundaries; not a simulator run."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location("smoke", ROOT / "Scripts/ci/smoke_simulator_launch.py")
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)
SIM = "12345678-1234-4234-8234-123456789ABC"
BUNDLE = "app.claw.synthetic"


class SmokeChecks(unittest.TestCase):
    def exercise(self, failure=None):
        fixture_root = Path(__file__).resolve().parent / ".fixtures"
        fixture_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=fixture_root) as temporary:
            home = Path(temporary).resolve()
            self.assertTrue(home.is_relative_to(fixture_root.resolve()))
            build = home / "build"
            result = build / "ios-01-a-synthetic"
            app = result / "DerivedData/Build/Products/Debug-iphonesimulator/Tinodios.app"
            app.mkdir(parents=True)
            (app / "Tinodios").write_bytes(b"synthetic executable")
            (app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "Tinodios",
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
            }))
            archive = result / "CLAW-OS-unsigned-simulator.zip"
            archive.write_bytes(b"synthetic archive")
            (result / "simulator-id.txt").write_text(SIM)
            (result / "simulator-manifest.json").write_text(json.dumps({
                "commit": "fixture-sha", "artifact": archive.name,
                "sha256": smoke.sha256(archive), "bundle_id": BUNDLE,
            }))
            installed = home / SIM / "App.app"
            installed.mkdir(parents=True)
            (installed / "Tinodios").write_bytes((app / "Tinodios").read_bytes())

            def command(args, **kwargs):
                code, output = 0, ""
                if args[0] == "/bin/ps":
                    output = "1234 S Tinodios"
                elif args[2] == "list":
                    output = json.dumps({"devices": {"iOS-Synthetic": [{
                        "udid": SIM, "isAvailable": True, "state": "Booted"}]}})
                elif args[2] == "install" and failure == "install":
                    code = 1
                elif args[2] == "get_app_container":
                    output = str(installed)
                elif args[2] == "terminate":
                    code = 3  # Already stopped is harmless preparation, never launch evidence.
                elif args[2] == "launch":
                    output = BUNDLE + (": not-a-pid" if failure == "pid" else ": 1234")
                    if failure == "crash":
                        reports = home / "Library/Logs/DiagnosticReports"
                        reports.mkdir(parents=True)
                        (reports / "Tinodios_synthetic.ips").write_text('{"pid":1234,"procName":"Tinodios"}')
                elif args[2] == "io":
                    if failure == "screenshot":
                        code = 1
                    else:
                        Path(args[-1]).write_bytes(b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR"
                                                  + (390).to_bytes(4, "big") + (844).to_bytes(4, "big"))
                return subprocess.CompletedProcess(args, code, output, "")

            executable = home / "other-app" if failure == "path" else installed / "Tinodios"
            with patch.object(smoke.sys, "platform", "darwin"), \
                 patch.dict(os.environ, {"GITHUB_SHA": "fixture-sha", "GITHUB_RUN_ID": "fixture"}), \
                 patch.object(smoke.subprocess, "run", side_effect=command), \
                 patch.object(smoke, "process_path", return_value=executable.resolve()), \
                 patch.object(smoke.time, "sleep"), patch.object(smoke.Path, "home", return_value=home):
                if failure:
                    with self.assertRaises(RuntimeError):
                        smoke.run_smoke(build)
                else:
                    self.assertEqual(smoke.run_smoke(build)["status"], "PASS_COLD_LAUNCH_ONLY")
            manifest = json.loads((result / "launch-smoke/manifest.json").read_text())
            self.assertEqual(manifest["status"], "FAIL" if failure else "PASS_COLD_LAUNCH_ONLY")
            self.assertEqual(manifest["ui_journey"], "NOT_RUN")
            if failure == "crash":
                self.assertEqual(len(manifest["crash_reports"]), 1)

    def test_success_is_limited_to_cold_launch(self): self.exercise()
    def test_install_failure_stays_failed(self): self.exercise("install")
    def test_invalid_launch_pid_stays_failed(self): self.exercise("pid")
    def test_wrong_executable_stays_failed(self): self.exercise("path")
    def test_screenshot_failure_stays_failed(self): self.exercise("screenshot")
    def test_current_pid_crash_stays_failed(self): self.exercise("crash")


if __name__ == "__main__":
    unittest.main()
