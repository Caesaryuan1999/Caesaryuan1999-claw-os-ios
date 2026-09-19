# CI44 — actual native compilation failure

Candidate `600be3abd889fe2a2957e48129759e933fc407d6`, run `35468965216`, job `105966326378`, attempt 1. Locked MobileVLCKit installation succeeded today. SDK **44/44 passed**. App-hosted/storage compilation failed before those tests ran; the six owned-AU methods, navigation, package, and cold launch are **NOT_RUN**.

Original artifact `10591992228`: 810287 bytes, SHA-256 `36d3519fc77a5b20e8c5be9f5b2aea1ba1a8f4fc7c4e85ff90385a9e1a387fc2`. The original ZIP and download receipt are retained locally under `evidence/CI44-evidence.zip` and `evidence/CI44-evidence.download.json`. SDK/storage summaries and the original `storage.log` remain in that archive; no source-red evidence is replaced.

Actual compiler diagnostic at `TinodiosUITests/VoiceLayoutTests.swift:487:30`: `'nil' is not compatible with expected argument type 'Data'`. `TinodeSDK/model/Drafty.swift:505` declares `insertAudio(... preview: Data, ...)`. Both new mixed-AU fixture calls supplied `nil`, although this parameter is nonoptional. The correct no-preview fixture is `Data()`; the SDK omits an empty preview. This is a fixture API mismatch, not an audio decoder or permission failure.

The successor changes exactly those two `preview` arguments in the existing test method. All 17 method names, all assertions, timeouts, AAC payloads, metadata extremes, real renderer/owner consumer, and production files remain unchanged. No Pod, PBX, selector, workflow, or dependency change. Reverse substitution of these two lines restores the entire fixed 600 test blob exactly. `git diff --check` passes. Native verification of the correction is pending one necessary successor run; **327 native + 3 navigation remains an expectation, not a pass count**.

The separately committed visual plan is docs-only (`6bd38ea1805668ba094a9feddbea8d88d53fae38`); visual implementation has not started. The original CI44 failure is retained. To reverse only this fixture repair in an isolated review branch, restore these two arguments from the preceding commit; doing so restores the known compile failure. No database/data operation is involved.
