# LICENSE — valid XML without changing license text

Parent: 8712f7b305f197411f1803efc23b21a6187a2e08.
Three implementation/resource files: Podfile, Scripts/ci/prepare_license_plist.py, Tinodios/Settings.bundle/Acknowledgements.plist.
Additional regression and evidence wiring: test_license_plist.py and ios-smoke.yml. No Swift/auth/SDK/DB/UI change.

R3 CI1 run35273737985 at 7f0b8a4 completed pod install, then failed the generated-resource parser with ExpatError line2581 column0. Swift methods executed: 0. No simulator App was produced.
Podfile previously copied Pods-Tinodios-acknowledgements.plist byte-for-byte to Settings.bundle. The inherited local resource has exactly nine XML-forbidden 0x0C form-feed page separators inside MobileVLCKit's GNU LGPL text; first occurrence is line2581. Other 24 entries and the visible LGPL wording remain intact. Current CI1 raw generated file was not archived, so matching location plus the copy chain identifies the cause; the next CI now archives the actual generated input and hash.

post_install now calls the Python preparation script. It removes only C0 bytes forbidden by XML1.0 (keeps TAB/LF/CR and every other byte), then strictly parses the result and requires named license text. Any remaining malformed XML/encoding, wrong format, or missing licenses raises and leaves the prior destination unchanged. On success, an atomic same-directory replace installs the prepared resource. It never serializes/reformats the plist or rewrites license wording.
The original generated file and manifest (hashes, offsets, removed-byte counts, parse result/titles) are retained under build/licenses and included in the existing CI artifact even on parse failure.
The existing generated and final bundled license parse gates remain enabled.

Windows actual script execution on the inherited full resource: original SHA30412a30942c46b6ae32b435079c5545df01156460286f33e78112edc41a169d; removed only nine FF bytes; strict parse25 entries PASS. Independent comparison proves output equals the original with exactly those bytes omitted; see transform.json for final SHA and Git-parent LF blob SHA (checkout resource has CRLF).
Six real Python regressions PASS: already-valid input byte identity; all forbidden C0 removal with visible text retained; malformed XML leaves destination intact; non-C0 invalid UTF8 is not repaired; missing license list rejected; actual resource retains MobileVLCKit LGPL and all entries.
Initial added invalid-UTF8 fixture accidentally used a literal backslash escape, correctly causing one assertion failure; corrected to bytes([255]) without changing production parser. Initial failed policy evidence retained. Final suite34/34 PASS, including these6 production-script tests. Git diff-check PASS.
Ruby/CocoaPods execution and next Mac Swift/App/native106 remain pending parent CI2. No local provider/device acceptance is claimed.
