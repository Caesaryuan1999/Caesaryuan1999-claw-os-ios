# R4-MEDIA-FINISH01 / ordinary AU owned playback

## Fixed source and scope

- Worktree: `work/r3-20260918-ios`; branch: `codex/r3-20260918-ios`.
- Baseline: `86cf0fa87a28946c56a87e1e3eb67a51e4dbaa84`; approved plan: `27db0e4be1ec6fa5c9c43b0581a40b95edaa2423`.
- Five-source implementation: `d4528a668342ca52a9fd064676ebda53f71cac68`.
- Narrow seek successor: `01d34caba9f73353e9fc60e350ae3484e7f5bbdd`. After actual playback ends, seeking changes the state to paused before preserving the requested currentTime. A later explicit play therefore resumes that position instead of resetting to zero. This is one added production line; d452 remains the original reviewable candidate.
- Production paths: `Tinodios/MessageCell+VLCMediaPlayerDelegate.swift`, `Tinodios/MessageCell.swift`, `Tinodios/MessageViewController+MessageCellDelegate.swift`, `Tinodios/MessageViewController.swift`, `Tinodios/MessageViewController+SendMessageBarDelegate.swift`.
- The fifth file only retires ordinary playback before recording or recorded-preview playback. The cb296 recording limit/submission branches remain unchanged. No SDK, database, protocol, Pod, project, selector, workflow, or private configuration change.

## Resulting behavior

Ordinary AU playback captures the original SDK owner, account, page, cell binding, message identity, entity value, and attempt. Remote bytes use the existing owned downloader with an explicit `min(original negotiated maximum, 8 MiB)` playback input budget. AVAudioPlayer receives only complete Data; there is no URL/VLC fallback. Actual engine play/isPlaying/currentTime govern playing state and finite position. A replaced cell, inactive/leaving page, audio interruption, invalid owner, or stale delegate retires the captured attempt. Owner polling is bounded at 250 ms while active; it is not an instantaneous-stop guarantee.

Unsupported/oversized inputs offer an explicit original-file download under the original context and original server file budget, followed by existing system sharing. No automatic fallback request or fake playback is added. Filename/suffix does not grant a decoder or network capability.

Current AAC/M4A recording samples are the compatibility baseline. Historical Ogg/Opus and other containers may be unsupported by AVAudioPlayer; failure is explicit and original-file recovery remains available within its budget. This is not a claim that all historical audio formats play. Historical durations above 60 seconds are not cut off; the recording limit is separate.

## Evidence and six new methods

`TinodiosUITests/VoiceLayoutTests.swift` remains in its existing App-hosted target and existing class selector. It has 17 methods: the original 11 methods and helpers are exactly preserved after removing this unit's additions/import changes. `check-source.py` verifies this reversal and the fixed five production files; `test-source-checks.json` records names and the current test-file raw hash.

| Added method | Actual consumer prepared for Mac | Limit |
|---|---|---|
| `testOwnedAudioActualAACPlaybackPauseResumeAndFiniteSeek` | Generated AAC, real AV engine/time, pause/resume/finite seek, natural finish then seek/resume, real 61-second asset | No microphone or hardware-audibility claim |
| `testOwnedAudioActualCellsBindEntityAndRetireOnReuseAndInactive` | Original renderer, MessageCell, MessageViewLayout, page handler, two AU entities | Controlled current-slot admission and inactive-handler call; not OS background delivery or a logged-in chat |
| `testOwnedAudioRealHTTPRefusalAndExplicitOriginalDownload` | Real loopback TCP, existing URLSession owned download, AAC/403/redirect/size/error/export | External HTTPS headers use the actual request factory only; no external connection or system-share UI |
| `testOwnedAudioPlaylistDataCannotReadSecondaryHTTP` | Original M3U/PLS bytes to real AVAudioPlayer(data:), isolated loopback observer | One-second observation of these exact fixtures; not an all-format isolation proof |
| `testOwnedAudioMemoryLimitAndInvalidSourcesPreserveOriginalBytes` | Real controller budgets and invalid source rejection; no inline fallback when ref is invalid | Synthetic oversized bytes and URLs |
| `testOwnedAudioRetiredOwnerAndLateAVCallbackCannotAlterNewAttempt` | Real isolated SDK/SQLite account switch, real engines, actual delegate consumer and main FIFO barrier | Controlled stale callback/current-slot fixture, not a delayed OS callback or real login |

The loopback listener installs its connection handler before start, binds only 127.0.0.1, and uses a retained non-main serial queue. Request evidence contains ordinal/auth-presence only. AAC and playlist attachments contain synthetic data only. The fixture never records a microphone or connects to a real account/service.

- `source-red.json`: fixed 86cf source counterexamples, **not executed Swift red tests**.
- d452 independently source-reviewed by root and backend (`09933d4e`); no new definite P1/P2 found within the five-source scope.
- `source-policies.json` and `source-policies-final.json`: earlier 44/44 source-policy results retained.
- `source-policies-seek-final.json`: final 44/44 source-policy result with the one-line seek successor and prepared tests.
- `test-source-checks.json`: old 11/source-boundary checks PASS. `git diff --check` on the changed test file PASS.
- **Swift compilation, six new native methods, simulator audio, and device execution: NOT_RUN.** Expected cumulative selection is **327 native + 3 navigation**, not a pass count. This window performed no push or CI dispatch. The existing MobileVLCKit official-download blocker is retained; it was not bypassed or repeatedly retried.

## Remaining boundaries and recovery

`RESOURCE-CLEANUP-INHERITED`: the caller retains/retries cleanup responsibility only for export URLs delivered to it. Existing downloader internal cancel/invalid-success cleanup and system-sharing completion can consume `removeExport(false)` without returning the URL; they have no guaranteed caller retry. Final deinit cleanup failure has no persisted responsibility. Do not infer all-path or cross-restart deletion guarantees.

The ordinary audio toggle remains the existing 24-point attachment. Full 48-point voice visuals, whole-bubble interaction, and waveform/progress design are a later unit. Video and recorded-preview VLC paths remain unchanged. Controlled finite playlist evidence must not be promoted to a universal parser/network-security proof.

For source recovery, preserve the current checkout and private files first. These are reviewable ordinary Git commits, not an installable signed release: apply d452 to its exact plan parent, then 01d34ca, then the separate test/docs successor. To abandon the candidate in a separate integration branch, reverse the test/docs successor, then 01d34ca, then d452, in that order. Reverting production restores the previous ordinary-AU risks; it is not a security recommendation. No database migration or data rollback is required by this unit. Do not reset/clean the shared worktree or replace private configuration.
