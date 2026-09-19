# CI46 actual results and narrow successors

Exact tested source: `aaeab1b1b8527606107393aeb11d795072e76718`; run `35470676087`, job `105970951872`, attempt 1. The job ended naturally; intermediate log snapshots were not proof of a hung process. Existing job limit remained 45 minutes.

Original artifact `10592579074`: 113,507,782 bytes, SHA-256 `8da31e1621bf45d1e015bd79e6a3baf76a8578ced99ca3969690f5b9e617de02`. Original ZIP is `evidence/CI46-evidence.zip`; safely extracted files are under `evidence/CI46-original/ios-01-a-20260919-213231`. `CI46-EVIDENCE-INDEX.json` binds 26 selected original entities to method, filename, byte count and SHA-256. No screenshot was redrawn.

- SDK 44 passed; storage 281 passed / 2 failed / 0 skipped. Total 327 methods: 325 passed / 2 failed.
- VoiceLayout 17: old 11 passed; new AU six were five passed / one failed.
- CoreList six: five passed / one failed. Both failures are described separately below.
- B1/B02 Run 17, Stream 9, KnownRun 13 and KnownRunLayout 5 passed. These do not prove provider availability or real production integration.
- Navigation, unsigned packaging and cold launch were not executed after the test failure.

## Original native pictures

Environment: macOS 15.7.9, iPhone 16 Pro simulator / iOS 18.5 (22F77), UUID `DC4CD8B3-4457-4153-9087-A0D7A2F9BFD9`.

`testContinuousAudioWidthsReachRealFormatterAndMessageCells` produced `9A506ACA-D25A-4C7B-9A8F-FC05B1EDEA3A.png` and `86763BFD-26C2-40BD-AE5A-A034A03A8390.json`. These are actual FullFormatter / MessageCell / MessageViewLayout rendering with synthetic Drafty AU content and local direction inputs, not an authenticated chat or the proposed new compact voice view. The visible final sample is the existing speaker/time presentation at 60 seconds. The other two existing renderer methods produced the indexed `audio-width-small-*` and `audio-width-stable-width-and-hit-*` originals.

The six playback methods' generic `voice-component-teardown-current-before-reset` PNGs show the shared recording-bar fixture, not AU playback. Do not label those as successful AU playback screenshots. The failed AAC method exported its four-second AAC source as `BDCFA01C-F0C1-45C2-9691-BBAF7B3DEB3F.mp4` (original export extension); the one-second natural-finish source was not separately attached in CI46. Its final `actual-aac` JSON was not reached.

## AAC failure and test-only successor

`VoiceLayoutTests.testOwnedAudioActualAACPlaybackPauseResumeAndFiniteSeek` failed after 4.025 seconds. Original log lines 22087–22091 show only `VoiceLayoutTests.swift:116: Component condition failed: actual AAC finish delegate`. The awaited condition is line 452. Earlier real engine play, clock, pause, same-engine resume and finite seek assertions were reached; assertions after natural completion were not.

The original entire method executes inside `main {}` (including `DispatchQueue.main.sync` when invoked off-main). Its completion wait repeatedly pumps RunLoop inside that block. The actual production delegate always schedules its state mutation using `DispatchQueue.main.async`. This creates a concrete scheduling concern; CI46 did not record callback entry or engine state at timeout, so it does not dynamically establish the sole cause or a production playback defect.

The authorized successor changes only this one method and adds a test-only forwarding delegate. Synchronous UIKit/AV operations remain in `MainActor.run`; the completion wait leaves that block and uses `await fulfillment(of:timeout: 3)`. A real AV callback is recorded then forwarded unchanged to the same production receiver. The test never synthesizes completion or swaps the player. Teardown preserves finite engine metrics, callback thread/identity/success and actual state changes even on failure; the one-second source is now also attached. All 17 original assertion lines remain, and the other 16 methods and existing helpers remain byte-equal after LF normalization. The method count stays 17, cumulative native count 327.

The project uses Swift language mode 5 and iOS deployment target 14.0. The current [Apple fulfillment documentation](https://developer.apple.com/documentation/xctest/xctestcase/fulfillment(of:timeout:enforceorder:)) / official DocC metadata reports iOS 13.0 availability; [Apple asynchronous tests](https://developer.apple.com/documentation/xctest/asynchronous-tests-and-expectations) describes asynchronous verification. No target, dependency or timeout changed. Windows has no Swift/UIKit runtime: the successor remains **NOT_RUN** until a reviewed Mac run.

## Separate help-page failure

`CoreListLayoutTests.testRealAccountAt320AccessibilityGrowsWithoutClippingOrInventedEntries` failed at line 555, inside `closedHelp`, in the retained `readable(label); contained(label, in: cell.contentView)` checks. It is not the account-header/contentSize assertion. Original `1667D8D3-D1A3-42A7-8639-A2B8C66D65AD.json` and `5B18AB10-A946-4876-A002-6FD7E21C2CAC.png` show the actual help page at large accessibility text. The label is 232 points wide and 400 high, while the text requires about 429.667 points. The final “言。” is clipped. The production row estimate uses a different 280-point width. Backend independently confirmed this geometry; its narrow production fix is a separate commit, with existing text/font/semantics and readability assertions preserved.

## Preservation / rollback

CI44/45 compiler failures, CI46 originals, the integration's untracked material, and the new visual child worktree are retained. The visual WIP was paused at CI46 failure and is not part of this successor. No push or new CI was performed for this document/test change. Revert the standalone AAC test commit to restore exact `aae` behavior; no DB, protocol, playback production or media payload changes are involved.
