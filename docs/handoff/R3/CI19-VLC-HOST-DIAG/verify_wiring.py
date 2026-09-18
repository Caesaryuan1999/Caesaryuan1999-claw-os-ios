"""Windows static graph/source verification; never a Swift build or playback result."""
import hashlib
import json
import re
import subprocess
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
BASE = "c1338e7bc22f5ebc5f5e3c9d3edad9d7a6f7eb88"
def read(path):
    return (ROOT / path).read_text(encoding="utf-8")
def old(path):
    return subprocess.check_output(["git", "show", BASE + ":" + path], cwd=ROOT).decode("utf-8")
def parse(text):
    tokens = re.findall(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text, re.S)
    tokens = [t for t in tokens if not t.startswith(("/*", "//"))]
    index = 0
    def take(expected=None):
        nonlocal index
        value = tokens[index]
        index += 1
        if expected is not None:
            assert value == expected, (expected, value)
        return value
    def value():
        first = take()
        if first == "{":
            result = {}
            while tokens[index] != "}":
                key = take()
                key = json.loads(key) if key.startswith('"') else key
                assert key not in result, "Duplicate OpenStep key"
                take("=")
                result[key] = value()
                take(";")
            take("}")
            return result
        if first == "(":
            result = []
            while tokens[index] != ")":
                result.append(value())
                if tokens[index] == ",":
                    take(",")
                else:
                    assert tokens[index] == ")"
            take(")")
            return result
        return json.loads(first) if first.startswith('"') else first
    result = value()
    assert index == len(tokens)
    return result

checks = []
def check(name, condition):
    assert condition, name
    checks.append(name)
project_path = "Tinodios.xcodeproj/project.pbxproj"
before = parse(old(project_path))
after = parse(read(project_path))
objects = after["objects"]
base_objects = before["objects"]
host = "C1A044000000000000000006"
test = "C1A044000000000000000007"
ui = "0AE21E4A28D21849008F486C"
probe_ref = "C1A043012026091800000001"
changed = {key for key in base_objects if base_objects[key] != objects[key]}
check("existing graph changes exactly four allowed objects",
      changed == {"0A0380CB21B3CC8100A3FA0E", "0A0380D521B3CC8100A3FA0E",
                  "0A0380CC21B3CC8100A3FA0E", "0AE21E4728D21849008F486C"})
check("only new host application and unit target",
      objects[host]["productType"] == "com.apple.product-type.application"
      and objects[test]["productType"] == "com.apple.product-type.bundle.unit-test")
check("original UI runner type preserved", objects[ui] == base_objects[ui])
def source_refs(target):
    result = []
    for phase in objects[target]["buildPhases"]:
        if objects[phase]["isa"] == "PBXSourcesBuildPhase":
            result += [objects[f]["fileRef"] for f in objects[phase]["files"]]
    return result
check("probe removed only from UI runner", probe_ref not in source_refs(ui))
check("host compiles only its empty delegate", len(source_refs(host)) == 1)
check("probe target compiles exact probe and existing context source",
      set(source_refs(test)) == {probe_ref, "C1A040012026091800000001"})
check("probe source is compiled by one target",
      sum(probe_ref in source_refs(key) for key, item in objects.items()
          if item["isa"] == "PBXNativeTarget") == 1)
for target in (host, test):
    configs = objects[objects[target]["buildConfigurationList"]]["buildConfigurations"]
    for config in configs:
        settings = objects[config]["buildSettings"]
        check(target + " " + objects[config]["name"] + " no install/signing identity",
              settings["SKIP_INSTALL"] == "YES" and settings["DEVELOPMENT_TEAM"] == "")
        if target == test:
            check("hosted loader " + objects[config]["name"],
                  settings["BUNDLE_LOADER"] == "$(TEST_HOST)"
                  and settings["TEST_HOST"] == "$(BUILT_PRODUCTS_DIR)/TinodiosVLCProbeHost.app/TinodiosVLCProbeHost")
deps = objects[test]["dependencies"]
check("unit target depends on dedicated host",
      len(deps) == 1 and objects[deps[0]]["target"] == host)
frameworks = {"0A431C022244A26200A837F7", "0ACE9E7E23814157006BE575"}
for target in (host, test):
    phase = next(objects[k] for k in objects[target]["buildPhases"] if objects[k]["isa"] == "PBXFrameworksBuildPhase")
    check("SDK DB links " + target, {objects[f]["fileRef"] for f in phase["files"]} == frameworks)
embed = next(objects[k] for k in objects[host]["buildPhases"] if objects[k]["isa"] == "PBXCopyFilesBuildPhase")
check("host embeds SDK DB without changing frameworks",
      embed["dstSubfolderSpec"] == "10" and {objects[f]["fileRef"] for f in embed["files"]} == frameworks)
scheme = ET.fromstring(read("Tinodios.xcodeproj/xcshareddata/xcschemes/Tinodios.xcscheme"))
testables = scheme.findall("./TestAction/Testables/TestableReference/BuildableReference")
check("scheme has existing UI testable and new hosted target once",
      [item.attrib["BlueprintIdentifier"] for item in testables] == [ui, test])
check("empty host not an archive or launch product",
      all(item.attrib.get("BlueprintIdentifier") not in (host, test)
          for item in scheme.findall("./BuildAction//BuildableReference") + scheme.findall("./LaunchAction//BuildableReference")))
lock = read("Podfile.lock")
check("dependency lock unchanged except Podfile checksum",
      re.sub(r"(?m)^PODFILE CHECKSUM: .*$", "", lock) == re.sub(r"(?m)^PODFILE CHECKSUM: .*$", "", old("Podfile.lock")))
check("Podfile checksum matches committed LF source",
      re.search(r"(?m)^PODFILE CHECKSUM: (.*)$", lock).group(1) == hashlib.sha1(read("Podfile").encode()).hexdigest())
script = read("Scripts/ci/verify_publish_outcomes_macos.sh")
selectors = re.findall(r"-only-testing:([^\s\\]+)", script)
prior_selectors = re.findall(r"-only-testing:([^\s\\]+)", old("Scripts/ci/verify_publish_outcomes_macos.sh"))
check("only VLC selector changed, no duplicate",
      selectors == [s.replace("TinodiosUITests/VLCPlaybackProbeTests", "TinodiosVLCProbeTests/VLCPlaybackProbeTests") for s in prior_selectors]
      and len(selectors) == len(set(selectors)))
swift = read("TinodiosUITests/VLCPlaybackProbeTests.swift")
prior = old("TinodiosUITests/VLCPlaybackProbeTests.swift")
check("same four methods",
      re.findall(r"func (test\w+)\(", swift) == re.findall(r"func (test\w+)\(", prior))
a = "    private func decoded("
b = "    private func validateBaseline("
check("original frame/display/time predicate unchanged", swift.split(a)[1].split(b)[0] == prior.split(a)[1].split(b)[0])
check("original loopback server unchanged",
      swift.split("private final class VLCProbeServer")[1].split("private final class VLCProbeAccount")[0]
      == prior.split("private final class VLCProbeServer")[1].split("private final class VLCProbeAccount")[0])
check("all existing 8 second playback waits retained",
      swift.count("until(8,") == prior.count("until(8,") and "executionTimeAllowance = 120" in swift)
check("no new VLC decoder/vout options", "addOptions" not in swift and "VLCMediaPlayer(options:" not in swift)
check("raw input attachment precedes Apple readback",
      swift.index('attachment.name = label') < swift.index("try readFixture(url, blue: blue)"))
check("actual Apple decoded pixels plus same-source local control",
      "AVAssetReaderTrackOutput" in swift and "CMSampleBufferGetImageBuffer" in swift
      and "vlc-same-source-local-control" in swift)
host_source = read("TinodiosVLCProbeHost/AppDelegate.swift")
check("empty host source only imports UIKit and creates visible window",
      re.findall(r"^import (\w+)", host_source, re.M) == ["UIKit"]
      and "window.makeKeyAndVisible()" in host_source and "Tinode(" not in host_source)
counts = {}
for selector in selectors:
    target, name = selector.split("/")
    folder = ROOT / ("TinodeSDKTests" if target == "TinodeSDKTests" else "TinodiosUITests")
    matches = []
    for source in folder.glob("*.swift"):
        source_text = source.read_text(encoding="utf-8")
        found = re.search(r"(?m)^(?:final )?class " + re.escape(name) + r"\b", source_text)
        if found:
            tail = source_text[found.start():]
            next_class = re.search(r"(?m)^(?:final )?class \w+", tail[1:])
            if next_class:
                tail = tail[:next_class.start()+1]
            matches.append(len(re.findall(r"func test\w+\(", tail)))
    assert len(matches) == 1, selector
    counts[selector] = matches[0]
check("200 native plus 3 navigation methods", sum(v for k,v in counts.items() if "IdentityNavigation" not in k) == 200
      and counts["TinodiosUITests/IdentityNavigationUITests"] == 3)
expected_wip = {
 "Tinodios/MediaRecorder.swift": "443cfb826b7d855e5bde822d1d8a4b18a82214c3ab14350180b865990ab87435",
 "Tinodios/Cache.swift": "62796522dc30f008d2023f4548a777995adc53508e7f0c2549442fbe821d8378"}
check("voice WIP raw hashes unchanged",
      all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest() == sha for p,sha in expected_wip.items()))
report = {"base": BASE, "scope": "Windows static OpenStep graph, source and lock checks; not Xcode/Swift/native",
          "checks": checks, "count": len(checks), "method_counts": counts,
          "native_execution": "NOT_RUN; next exact Mac CI required"}
Path(__file__).with_name("wiring-checks.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"static_checks": len(checks), "method_counts": counts}))
