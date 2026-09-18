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
    def exercise(self, failure=None, initial_state="Booted", simulator_available=True):
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

            observed_state = initial_state
            calls = []

            def command(args, **kwargs):
                nonlocal observed_state
                calls.append(args)
                code, output = 0, ""
                if args[0] == "/bin/ps":
                    output = "1234 S Tinodios"
                elif args[2] == "list":
                    entries = [{"udid": SIM, "isAvailable": simulator_available, "state": observed_state}]
                    if failure == "missing":
                        entries[0]["udid"] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
                    elif failure == "duplicate":
                        entries += entries.copy()
                    output = json.dumps({"devices": {"iOS-Synthetic": entries}})
                elif args[2] == "boot":
                    self.assertEqual(args[3], SIM)
                    if failure == "boot":
                        code = 1
                elif args[2] == "bootstatus":
                    self.assertEqual(args[3:], [SIM, "-b"])
                    self.assertEqual(kwargs["timeout"], 45)
                    if failure == "boot-timeout":
                        raise subprocess.TimeoutExpired(args, 45)
                    if failure != "still-shutdown":
                        observed_state = "Booted"
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
            observations = manifest["simulator_observations"]
            if failure != "missing":
                self.assertEqual(observations[0]["matches"][0],
                                 {"runtime": "iOS-Synthetic", "state": initial_state,
                                  "isAvailable": simulator_available})
            if failure in ("missing", "duplicate", "unavailable", "boot", "boot-timeout", "still-shutdown", "unknown-state"):
                self.assertFalse(any(call[2] == "install" for call in calls if call[0] == "xcrun"))
            if initial_state == "Shutdown" and not failure:
                self.assertEqual(observations[-1]["matches"][0]["state"], "Booted")
                self.assertEqual([call[2] for call in calls if call[0] == "xcrun"][:4],
                                 ["list", "boot", "bootstatus", "list"])
            if failure == "boot-timeout":
                self.assertEqual(manifest["commands"][-1]["timeout_seconds"], 45)
            if failure in ("missing", "duplicate", "unavailable", "unknown-state"):
                self.assertFalse(any(call[2] in ("boot", "bootstatus") for call in calls if call[0] == "xcrun"))
            self.assertFalse(any(call[2] in ("create", "clone") for call in calls if call[0] == "xcrun"))

    def test_success_is_limited_to_cold_launch(self): self.exercise()
    def test_install_failure_stays_failed(self): self.exercise("install")
    def test_invalid_launch_pid_stays_failed(self): self.exercise("pid")
    def test_wrong_executable_stays_failed(self): self.exercise("path")
    def test_screenshot_failure_stays_failed(self): self.exercise("screenshot")
    def test_current_pid_crash_stays_failed(self): self.exercise("crash")
    def test_same_shutdown_device_boots_and_is_rechecked(self): self.exercise(initial_state="Shutdown")
    def test_missing_device_never_selects_another(self): self.exercise("missing")
    def test_unavailable_device_never_boots(self): self.exercise("unavailable", simulator_available=False)
    def test_ambiguous_device_stays_failed(self): self.exercise("duplicate")
    def test_boot_failure_prevents_install(self): self.exercise("boot", initial_state="Shutdown")
    def test_boot_wait_is_bounded_and_recorded(self): self.exercise("boot-timeout", initial_state="Shutdown")
    def test_boot_must_be_verified(self): self.exercise("still-shutdown", initial_state="Shutdown")
    def test_unknown_state_is_not_promoted(self): self.exercise("unknown-state", initial_state="Creating")


if __name__ == "__main__":
    unittest.main()
