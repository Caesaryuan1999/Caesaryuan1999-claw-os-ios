# CI37 unread badge shrink follow-up

Fixed source: `7f98f4f5f1f64baeeaa7cdc1f9bf9587b78c4a8e`; parent `1a9fc236b589d4b8d641101539a76f0022349797`. Only `Tinodios/widgets/ChatListViewCell.swift` and `TinodiosUITests/CoreListLayoutTests.swift` changed. B1's six unfinished files were copied and hashed in `artifacts/checkpoints/b1-before-ci37-core` before this unit; all six original hashes still match and none is in this commit.

## Preserved red evidence

CI37 ran `5c91a4b67f58b2be7ec957ddc38c0b3136274450`, run `35396881526`, job `105767658300`. The root-owned original archive SHA256 is `30cea1cf134354bb48148c741b3a9c2355e104fe72ab90eb31c77619facedded`. SDK 44 passed; storage 224 passed / 1 failed / 0 skipped. AssistantHistory's 15 and AssistantLayout's 6 passed. Navigation, packaging and cold launch did not run.

The Core test's line 322 expands helper line 168: **width + 1 >= height**, not a minimum font-height failure. Original `artifacts/integration/20260919/R4-ios-ci37-native-review/7A1F737E-4422-4F25-AF1B-0C115C2ECB0F.json` records font 12, width 28, height approximately 54, shaped text width 15.8709 after the tear-down layout/screenshot. The width shrank while height retained the AX geometry. The original AX sample was font 38 / width 62 / height 54. This is a real incoherent geometry observation, not evidence that one additional layout wait necessarily fixes it.

The XIB defines one own unary height (`iMo-f5-dnu`). Previously production selected the first height constraint each time, after stack changes, and relied on inherited UILabel Dynamic Type updates during parent layout. The old artifact does not identify the selected constraint or its constant. We do **not** claim it proved selection of `UISV-hiding`, nor a particular UIKit internal scheduling cause.

## Minimal repair and acceptance

Capture the original own height before stack installation, retain that identity, and update only it. Derive the badge font from the same current cell trait using the existing 12-point semibold caption base and UIFontMetrics; synchronize width and height before layout and on trait changes. Dynamic Type remains enabled; no font cap, size-to-fit, model or read-count change.

All six test method names, all 89 existing XCTAssert source lines, the three-second deadline, original trait/font waiting predicates and width >= height assertion remain. Additional native checks require one active own equal-height constraint, expected font-derived constant and matching actual height. Evidence adds all badge height constraints (identity/active/relation/priority/constant), font line height and expected height, with a new shrink-state original PNG/JSON. Hidden/show, single digit, AX -> standard -> AX, both appearances remain in the same original method. This is actual nib/UIKit consumer coverage pending execution, not a mirrored layout model.

Windows: `CI37-CORE-FIX-static.json` records 44/44 source policies; scoped `git diff --check` passed. `CI37-CORE-FIX-checks.json` binds the original red JSON, preserved assertion lines and B1 hashes. No Swift build or UIKit execution was performed here. Next exact candidate still expects **269 native + 3 navigation methods**; visual/native closure awaits root's Mac run and original attachments. Existing red artifacts and earlier packages are unchanged.

Rollback is the inverse of this two-path source commit after preserving any newer edits; do not reset the worktree or discard the B1 checkpoint. No SDK, protocol, DB, Pods, CI selector, workflow or private configuration changed.
