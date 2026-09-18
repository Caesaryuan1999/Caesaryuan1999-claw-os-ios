"""Production smoke runner with controlled macOS command boundaries; not a simulator run."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
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
    def exercise(self, failure=None, initial_state="Booted", simulator_available=True,
                 running=False, other_process=None):
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
            previous_running = running
            scan_count = 0
            lookups = []
            calls = []

            def command(args, **kwargs):
                nonlocal observed_state, previous_running, scan_count
                calls.append(args)
                code, output = 0, ""
                if args[0] == "/bin/ps":
                    if args[1:] == ["-axo", "pid=,ucomm="]:
                        scan_count += 1
                        output = "9 unrelated-process"
                        if previous_running or other_process:
                            output += "\n8001 " + ("TinodiosHelper" if other_process == "prefix" else "Tinodios")
                        if failure == "scan-error" or (failure == "post-scan-error" and scan_count == 2):
                            code = 1
                        elif failure == "scan-malformed":
                            output = "not-a-pid Tinodios"
                        elif failure == "scan-empty":
                            output = ""
                        elif failure == "scan-duplicate":
                            output = "8001 Tinodios\n8001 Tinodios"
                    else:
                        self.assertEqual(args, ["/bin/ps", "-p", "1234", "-o", "pid=,stat=,ucomm="])
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
                    self.assertTrue(previous_running, "Never terminate an app proven absent")
                    self.assertEqual(args[3:], [SIM, BUNDLE])
                    self.assertEqual(kwargs["timeout"], 45)
                    if failure == "terminate-timeout":
                        raise subprocess.TimeoutExpired(args, 45)
                    if failure == "terminate-error":
                        code = 1
                    if failure != "terminate-residual":
                        previous_running = False
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

            def lookup(candidate_pid):
                lookups.append(candidate_pid)
                if candidate_pid == 8001:
                    if failure == "lookup":
                        raise RuntimeError("Cannot resolve app PID executable path")
                    if failure == "same-device-path":
                        return (home / SIM / "Unexpected.app/Tinodios").resolve()
                    if other_process == "other-device":
                        return (home / "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA/Other.app/Tinodios").resolve()
                    return (installed / "Tinodios").resolve()
                self.assertEqual(candidate_pid, 1234)
                return (home / "other-app" if failure == "path" else installed / "Tinodios").resolve()
            with patch.object(smoke.sys, "platform", "darwin"), \
                 patch.dict(os.environ, {"GITHUB_SHA": "fixture-sha", "GITHUB_RUN_ID": "fixture"}), \
                 patch.object(smoke.subprocess, "run", side_effect=command), \
                 patch.object(smoke, "process_path", side_effect=lookup), \
                 patch.object(smoke.time, "sleep"), patch.object(smoke.Path, "home", return_value=home):
                if failure:
                    with self.assertRaises(RuntimeError):
                        smoke.run_smoke(build)
                else:
                    self.assertEqual(smoke.run_smoke(build)["status"], "PASS_COLD_LAUNCH_ONLY")
            manifest = json.loads((result / "launch-smoke/manifest.json").read_text())
            self.assertEqual(manifest["status"], "FAIL" if failure else "PASS_COLD_LAUNCH_ONLY")
            self.assertEqual(manifest["ui_journey"], "NOT_RUN")
            self.assertTrue(all(item["elapsed_seconds"] >= 0 for item in manifest["commands"]))
            self.assertNotIn("unrelated-process", json.dumps(manifest))
            if not failure:
                self.assertEqual(manifest["cold_start_precondition"], "confirmed_not_running")
                processes = manifest["prelaunch_process_observations"]
                self.assertEqual(processes[0]["state"], "running" if running else "not_running")
                self.assertEqual(processes[-1]["state"], "not_running")
                self.assertEqual(processes[-1]["pids"], [])
                self.assertEqual(any(call[2] == "terminate" for call in calls if call[0] == "xcrun"), running)
            if other_process == "prefix":
                self.assertNotIn(8001, lookups)
            if other_process == "other-device":
                self.assertIn(8001, lookups)
            process_failures = {"scan-error", "scan-malformed", "scan-empty", "scan-duplicate",
                                "lookup", "same-device-path", "terminate-timeout", "terminate-error",
                                "terminate-residual", "post-scan-error"}
            if failure in process_failures:
                self.assertNotIn("cold_start_precondition", manifest)
                self.assertFalse(any(call[2] == "launch" for call in calls if call[0] == "xcrun"))
                self.assertEqual(manifest["status"], "FAIL")
            if failure == "terminate-timeout":
                self.assertEqual(manifest["commands"][-1]["timeout_seconds"], 45)
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
    def test_running_app_must_be_terminated_then_proven_absent(self): self.exercise(running=True)
    def test_same_name_on_another_device_does_not_get_terminated(self): self.exercise(other_process="other-device")
    def test_ucomm_prefix_is_not_a_target_process(self): self.exercise(other_process="prefix")
    def test_process_query_failure_never_means_absence(self): self.exercise("scan-error")
    def test_process_query_malformed_output_stays_failed(self): self.exercise("scan-malformed")
    def test_process_query_empty_output_stays_failed(self): self.exercise("scan-empty")
    def test_process_query_duplicate_pid_stays_failed(self): self.exercise("scan-duplicate")
    def test_unresolved_exact_name_pid_stays_failed(self): self.exercise("lookup", running=True)
    def test_same_device_wrong_container_stays_failed(self): self.exercise("same-device-path", running=True)
    def test_terminate_error_never_launches(self): self.exercise("terminate-error", running=True)
    def test_terminate_timeout_never_launches(self): self.exercise("terminate-timeout", running=True)
    def test_terminate_residual_process_never_launches(self): self.exercise("terminate-residual", running=True)
    def test_post_terminate_query_failure_never_launches(self): self.exercise("post-scan-error", running=True)
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


class NavigationExportChecks(unittest.TestCase):
    """Execute the real runner heredoc with controlled xcrun boundaries, not macOS export."""
    runner = (ROOT / "Scripts/ci/verify_publish_outcomes_macos.sh").read_text()
    source = runner.split("<<'EXPORT_NAVIGATION'\n", 1)[1].split("\nEXPORT_NAVIGATION", 1)[0]

    def exercise(self, case):
        fixture_root = Path(__file__).resolve().parent / ".fixtures"
        fixture_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=fixture_root) as temporary:
            result = Path(temporary).resolve()
            self.assertTrue(result.is_relative_to(fixture_root.resolve()))
            if case != "no-result":
                (result / "navigation.xcresult").mkdir()
            calls = []
            original = b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + (390).to_bytes(4, "big") + (844).to_bytes(4, "big")

            def command(args, **kwargs):
                calls.append(args)
                self.assertNotIn("--only-failures", args)
                if args[2] == "help":
                    self.assertEqual(args, ["xcrun", "xcresulttool", "help", "export", "attachments"])
                    text = "--path PATH --output-path PATH" if case != "help" else "unsupported command"
                    return subprocess.CompletedProcess(args, 0, text, "")
                self.assertEqual(args[:4], ["xcrun", "xcresulttool", "export", "attachments"])
                self.assertEqual(args[4:], ["--path", str(result / "navigation.xcresult"),
                                           "--output-path", str(result / "navigation-attachments")])
                self.assertEqual(kwargs["timeout"], 60)
                if case == "timeout":
                    raise subprocess.TimeoutExpired(args, 60)
                if case == "export":
                    return subprocess.CompletedProcess(args, 1, "", "controlled export error")
                if case != "empty":
                    payload = b"not PNG" if case == "invalid-image" else original
                    (result / "navigation-attachments" / "actual-attachment.png").write_bytes(payload)
                return subprocess.CompletedProcess(args, 0, "", "")

            with patch.object(subprocess, "run", side_effect=command), \
                 patch.object(smoke.sys, "argv", ["navigation-export", str(result)]), \
                 contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    exec(compile(self.source, "verify_publish_outcomes_macos.sh:EXPORT_NAVIGATION", "exec"), {})
            expected = 0 if case in ("success", "no-result") else 1
            self.assertEqual(raised.exception.code, expected)
            report = json.loads((result / "navigation-export-status.json").read_text())
            self.assertEqual(report["status"], "PASS_EXPORTED_ONLY" if case == "success"
                             else "NOT_RUN" if case == "no-result" else "FAIL")
            if case == "success":
                saved = result / "navigation-attachments" / "actual-attachment.png"
                self.assertEqual(saved.read_bytes(), original, "Exported image bytes must not be rewritten")
                self.assertEqual(report["screenshots"][0]["sha256"], hashlib.sha256(original).hexdigest())
                self.assertEqual(report["screenshots"][0]["width"], 390)
                self.assertTrue((result / "navigation-export-help.txt").is_file())
            if case == "no-result":
                self.assertEqual(calls, [])
            if case == "help":
                self.assertEqual(len(calls), 1, "Unsupported help must prevent export")
            if case == "timeout":
                self.assertEqual(report["commands"][-1]["timeout_seconds"], 60)

    def test_original_screenshots_are_exported_without_conversion(self): self.exercise("success")
    def test_unconfirmed_help_arguments_prevent_export(self): self.exercise("help")
    def test_failed_export_cannot_be_reported_as_success(self): self.exercise("export")
    def test_export_timeout_is_recorded_as_failure(self): self.exercise("timeout")
    def test_empty_export_is_not_visual_evidence(self): self.exercise("empty")
    def test_invalid_png_is_not_visual_evidence(self): self.exercise("invalid-image")
    def test_no_navigation_bundle_remains_not_run(self): self.exercise("no-result")

    def test_original_test_exit_code_has_priority_over_export(self):
        footer = self.runner.split(
            "  # Never replace an SDK/storage/navigation test failure with an export result.\n", 1)[1].split("\n}", 1)[0]
        bash = "C:/Program Files/Git/bin/bash.exe" if os.name == "nt" else shutil.which("bash")
        self.assertTrue(bash and Path(bash).is_file(), "Bash is required to check the real cleanup exit path")
        for original_status, export_status, expected in [(0, 0, 0), (65, 1, 65), (65, 0, 65), (0, 1, 1)]:
            script = f"original_status={original_status}\nexport_status={export_status}\n" + footer
            completed = subprocess.run([bash], input=script.encode("utf-8"), capture_output=True, check=False)
            self.assertEqual(completed.returncode, expected)


if __name__ == "__main__":
    unittest.main()
