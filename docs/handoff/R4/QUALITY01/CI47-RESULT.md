# CI47 — actual result and bounded AAC diagnosis

Source `db514ff4284aed249b4a073425c8379cce4d1943`, run `35473782593`, job `105979374086`, attempt 1. The independent image worktree remains clean at `4e2ba386`; it did not enter this run.

The original artifact `10593129262` was downloaded and verified: 101,874,295 bytes, SHA-256 `9da9932939b56ad2c69383b5eefb2a8e03b027099e9ad219ffed8580f36501fc`. ZIP: `evidence/CI47-evidence.zip`; extracted original logs, summaries and attachments: `evidence/CI47-original/ios-01-a-20260919-223620/`. The downloader's initial invocation incorrectly supplied the artifact digest as its source-SHA argument; its provenance check rejected that invocation before writing. The corrected invocation verified the exact source and artifact digest. No CI was retried.

Actual native result: **329 passed, 1 failed, 0 skipped** (SDK44; UIrunner178; VLC7; App-host100 passed/1 failed). Navigation, package and cold launch did not run. The original 11 VoiceLayout methods passed; six owned-AU methods were 5 passed/1 failed; three new compact-voice methods all passed. CoreList six passed, including the original closed-help clipping case and its font round trips. These are simulator tests, not a signed build, real conversation or device acceptance.

The only failure is `VoiceLayoutTests.testOwnedAudioActualAACPlaybackPauseResumeAndFiniteSeek`, line685: the actual finish expectation did not complete within the unchanged 3 seconds. Original `storage.log` lines22214–22222 record the method and failure. The source check/compile stages passed; this is an execution failure.

## Actual callback evidence

`storage-attachments/2F511865-3E39-4998-977A-A53A995B4FE7.json` retains the real forwarding delegate/state trace. Main-thread production timer observations continue every approximately 0.25 seconds. The one-second engine reaches `currentTime == duration == 1` at 1.251 seconds; through 3.256 seconds it still reports `isPlaying=true`, state playing, and no finish or decode-error callback. Successful same-engine finish count is zero. The 6.566-second paused/currentTime0.5 observation is subsequent test code after the failed wait, not a late successful finish. This evidence does not support the earlier whole-main-queue starvation hypothesis. Clock reaching duration is not an accepted substitute for an actual callback or production ended state.

The test creates a four-second player, pauses/resumes/seeks it to its end, then creates the separate one-second player without retiring the first. The real page's `ordinaryAudio(in:key:)` retires its previous ordinary player before creating another (MessageViewController+MessageCellDelegate.swift749–753). Concurrent fixture players are an uncontrolled variable, not a proven cause. A proposed narrow discrimination is to retain all pause/resume/seek assertions, retire the first player before the natural-finish phase, then compare an isolated production player and a sequential bare AVAudioPlayer with the same one-second bytes and real delegate. Keep each 3-second condition, callback identity/success, no synthetic finish, and no clock-only pass. No such successor has been implemented or run in this report.

The original one-second source is `C20B72FA-22B3-4145-8AF4-73E7E932B8A8.mp4` (audio attachment despite the exported extension). Independent ffprobe metadata is in `evidence/CI47-aac-ffprobe.json`; this is a file-format check, not Apple playback or delegate validation.

## Original native pictures

`evidence/CI47-native-evidence-index.json` maps and hashes 31 original entities: eight compact layout PNG/JSON pairs, actual playing/paused PNG/JSON pairs, five closed-help PNG/JSON pairs and the callback JSON. All were exported by XCTest, not regenerated.

Examples: normal incoming `E4E81012-8F62-4AB7-ACCA-1B524D6932D0.png`; AX dark outgoing `1975BC3D-44C0-4005-8832-763911235A8F.png`; actual playing `CA9E7083-D28A-4003-AA7F-6F3BA1DA43A9.png`; paused `8B2C26E0-E497-4990-B0B6-CBBB794A3EA8.png`; help AX dark `19CAE701-AF24-4D25-899E-5CCB414A8A7A.png`. These use real UIKit/MessageCell/MessageViewLayout and synthetic data, plus actual owned AV playback where named. They do not show an authenticated complete chat or a real user's recording. The help image visibly includes the former clipped final characters and its geometry records 454pt actual row height versus 429.667pt required text height at the actual 232pt label width.

Production, tests, deadlines, dependencies and remote branch remain unchanged. CI46 and CI47 failures are retained. Native end-of-playback acceptance remains OPEN.

## Authorized test-only successor (not yet run)

After the original result was preserved, root authorized one-method/helper discrimination. `VoiceLayoutTests.swift` now retires the initial four-second production player after preserving every pause/resume/finite-seek assertion and capturing its original identity evidence. It verifies that the actual engine stopped. A bare AVAudioPlayer and then an isolated production player use the exact same newly generated one-second byte buffer sequentially. The bare player is stopped before the production phase. Neither path synthesizes a callback, changes the decoder, forces completion from clock position, or extends its 3-second deadline.

Both waits use Apple's concurrency-safe `XCTWaiter.fulfillment(of:timeout:enforceOrder:)` to collect results. The bare result is saved before continuing to the production case; both must be `.completed`, and each real same-engine successful finish count must be one. Thus a failed control cannot be hidden by the production result. Original production `.ended`, subsequent paused seek, same-engine resume, and >60-second historical playback assertions remain. The original `same_engine` metadata is explicitly captured before retirement, not read from a retired wrapper.

The forwarding observer additionally records real loop count, delegate identity, session category/mode, output port **types** (no names/IDs), sample rate/channels and production scope. At-deadline attachments preserve each observation before cleanup. The bare timer only samples; it does not complete expectations. Original CI47 JSON remains unchanged.

Official API declaration and iOS13 availability were read from Apple's current documentation JSON and are below the existing iOS14 project minimum/18.5 runner (Swift5): [XCTWaiter concurrency-safe method](https://developer.apple.com/documentation/xctest/xctwaiter/fulfillment(of:timeout:enforceorder:)-swift.type.method). This API check does not replace compilation.

Local scope check: inverse replacement of only this method and its observer yields the exact prior LF-normalized file; other 19 methods and all other helpers are unchanged, all 18 original assertion lines remain, 20 methods total, `git diff --check` passes. Source remains one test file; production/PBX/selector/workflow/dependencies unchanged. Expected total remains330 native+3 navigation. macOS successor execution is **NOT_RUN**; the cause of the CI47 no-finish observation remains unproven. No successor push or dispatch has occurred.
