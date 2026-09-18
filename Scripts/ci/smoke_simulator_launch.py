#!/usr/bin/env python3
"""Cold launch only: one tested unsigned simulator app, no credentials or live service."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time
import uuid


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def process_path(pid):
    # Darwin host API: simulator app processes are ordinary host PIDs.
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    lookup = library.proc_pidpath
    lookup.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    lookup.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(4096)
    if lookup(pid, buffer, len(buffer)) <= 0:
        raise RuntimeError("Cannot resolve launched PID executable path")
    return Path(os.fsdecode(buffer.value)).resolve()


def run_smoke(build_root):
    build_root = Path(build_root).resolve()
    candidates = list(build_root.glob("ios-01-a-*/DerivedData/Build/Products/Debug-iphonesimulator/Tinodios.app"))
    if len(candidates) != 1:
        raise RuntimeError("Expected exactly one tested app")
    app = candidates[0].resolve()
    result = app.parents[4]
    if result.parent != build_root:
        raise RuntimeError("App escaped the expected result directory")
    output = result / "launch-smoke"
    output.mkdir(exist_ok=False)
    started = time.time()
    manifest = {
        "commit": os.environ.get("GITHUB_SHA"), "run": os.environ.get("GITHUB_RUN_ID"),
        "status": "FAIL", "scope": "Cold launch and process survival only; screenshot requires human review",
        "ui_journey": "NOT_RUN", "physical_device": "NOT_RUN", "real_service": "NOT_RUN", "push": "NOT_RUN",
        "commands": [], "crash_reports": [], "started_unix": started,
    }
    executable = None
    pid = None

    def command(label, args, required=True):
        try:
            completed = subprocess.run(args, capture_output=True, text=True, timeout=45, check=False)
        except subprocess.TimeoutExpired:
            manifest["commands"].append({"step": label, "returncode": None, "timeout_seconds": 45})
            raise RuntimeError(label + " exceeded 45 seconds") from None
        manifest["commands"].append({"step": label, "returncode": completed.returncode})
        if completed.returncode != 0 and required:
            raise RuntimeError(label + " failed with exit " + str(completed.returncode))
        return completed

    def verify_process(installed):
        record = command("process_status", ["/bin/ps", "-p", str(pid), "-o", "pid=,stat=,ucomm="]).stdout.strip()
        match = re.fullmatch(r"(\d+)\s+(\S+)\s+(.+)", record)
        if not match or int(match[1]) != pid or match[2][0] in "ZTX" or match[3] != executable:
            raise RuntimeError("Launched app is absent, stopped, zombie or not the expected executable")
        actual = process_path(pid)
        if actual != (installed / executable).resolve():
            raise RuntimeError("Launched PID does not belong to the installed tested app")
        manifest["process"] = {"pid": pid, "state": match[2], "executable": executable,
                               "path": str(actual), "path_method": "Darwin libproc.proc_pidpath"}

    def collect_crashes():
        if not executable:
            return
        directory = Path.home() / "Library/Logs/DiagnosticReports"
        for path in directory.glob(executable + "*"):
            if any(item["file"] == path.name for item in manifest["crash_reports"]):
                continue
            if path.suffix not in (".ips", ".crash") or path.stat().st_mtime < started:
                continue
            # Filter to this executable AND this exact launch PID before copying.
            data = path.read_text(encoding="utf-8", errors="replace")
            matching_pid = pid is not None and (
                re.search(r'"pid"\s*:\s*' + str(pid) + r'\b', data) or
                re.search(r'^Process:\s*' + re.escape(executable) + r'\s*\[' + str(pid) + r'\]', data, re.M))
            if not matching_pid:
                continue
            target = output / path.name
            shutil.copyfile(path, target)
            manifest["crash_reports"].append({"file": path.name, "sha256": sha256(target)})

    try:
        if sys.platform != "darwin":
            raise RuntimeError("Simulator launch smoke requires macOS")
        packaged = json.loads((result / "simulator-manifest.json").read_text())
        if not manifest["commit"] or packaged["commit"] != manifest["commit"]:
            raise RuntimeError("Packaged app commit mismatch")
        archive = result / packaged["artifact"]
        if archive.parent != result or sha256(archive) != packaged["sha256"]:
            raise RuntimeError("Packaged archive hash mismatch")
        manifest["tested_archive_sha256"] = packaged["sha256"]
        with (app / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        bundle = info["CFBundleIdentifier"]
        executable = info["CFBundleExecutable"]
        if bundle != packaged["bundle_id"] or not re.fullmatch(r"[A-Za-z0-9_.-]+", bundle):
            raise RuntimeError("Unexpected bundle identifier")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", executable) or "iPhoneSimulator" not in info["CFBundleSupportedPlatforms"]:
            raise RuntimeError("Expected simulator executable")
        manifest.update(bundle_id=bundle, executable=executable, binary_sha256=sha256(app / executable))
        sim_id = str(uuid.UUID((result / "simulator-id.txt").read_text().strip())).upper()
        manifest["simulator_id"] = sim_id
        manifest["simulator_observations"] = []

        def selected_simulator(label):
            devices = json.loads(command(label, ["xcrun", "simctl", "list", "devices", "--json"]).stdout)
            selected = [
                {"runtime": runtime, "state": device.get("state"), "isAvailable": device.get("isAvailable")}
                for runtime, entries in devices["devices"].items() if "iOS" in runtime
                for device in entries if device.get("udid", "").upper() == sim_id
            ]
            manifest["simulator_observations"].append({"step": label, "matches": selected})
            if len(selected) != 1:
                raise RuntimeError("The tested iOS simulator is missing or ambiguous")
            if selected[0]["isAvailable"] is not True:
                raise RuntimeError("The tested iOS simulator is unavailable")
            return selected[0]

        selected = selected_simulator("list_existing_devices")
        if selected["state"] == "Shutdown":
            command("boot_tested_device", ["xcrun", "simctl", "boot", sim_id])
            command("wait_tested_device_boot", ["xcrun", "simctl", "bootstatus", sim_id, "-b"])
            selected = selected_simulator("verify_tested_device_boot")
        if selected["state"] != "Booted":
            raise RuntimeError("The tested iOS simulator is not booted")
        command("install", ["xcrun", "simctl", "install", sim_id, str(app)])
        installed = Path(command("installed_container", ["xcrun", "simctl", "get_app_container", sim_id, bundle, "app"]).stdout.strip()).resolve()
        if sim_id not in str(installed).upper() or not installed.is_dir():
            raise RuntimeError("Installed container is not on the tested simulator")
        if sha256(installed / executable) != manifest["binary_sha256"]:
            raise RuntimeError("Installed executable differs from tested app")
        # App may already be absent; terminate is preparation, not evidence of a successful launch.
        command("terminate_previous", ["xcrun", "simctl", "terminate", sim_id, bundle], required=False)
        launched = command("launch", ["xcrun", "simctl", "launch", sim_id, bundle]).stdout.strip()
        match = re.fullmatch(re.escape(bundle) + r":\s*(\d+)", launched)
        if not match or int(match[1]) <= 0:
            raise RuntimeError("simctl did not return the expected bundle and PID")
        pid = int(match[1])
        manifest["launched_pid"] = pid
        time.sleep(5)
        verify_process(installed)
        screenshot = output / "cold-launch.png"
        command("screenshot", ["xcrun", "simctl", "io", sim_id, "screenshot", str(screenshot)])
        data = screenshot.read_bytes()
        if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
            raise RuntimeError("Screenshot is not a PNG")
        width, height = int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
        if width <= 0 or height <= 0:
            raise RuntimeError("Screenshot has no pixels")
        time.sleep(2)
        verify_process(installed)
        manifest["screenshot"] = {"file": screenshot.name, "sha256": sha256(screenshot),
                                  "width": width, "height": height, "login_screen_review": "PENDING_HUMAN"}
        collect_crashes()
        if manifest["crash_reports"]:
            raise RuntimeError("Crash report exists for the launched PID")
        manifest["status"] = "PASS_COLD_LAUNCH_ONLY"
    except Exception as error:
        manifest["failure"] = str(error)
        # Best-effort targeted diagnostics must never replace the original failure.
        try:
            collect_crashes()
        except Exception as diagnostic_error:
            manifest["diagnostic_error"] = type(diagnostic_error).__name__
        raise
    finally:
        manifest["finished_unix"] = time.time()
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-root", default="build")
    options = parser.parse_args()
    try:
        result = run_smoke(options.build_root)
        print(result["status"])
    except Exception as error:
        print("Simulator smoke failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
