# QUALITY01 — compact voice candidate

Production: `89ccf1b4d34513defecccec448bf74bfed44ee65` in the isolated `codex/r4-quality01-ios-voice` worktree. Seven approved entities only: MessageCell, MessageViewController, its MessageCellDelegate extension, and the two original PDF/catalog pairs. CI46 red fixes are inherited separately (`264cbba` / `c9bb6e7`, equivalent to integration `13b05b42` / `c0e4a43b`). No push or CI has been performed for this visual candidate.

Only exact standalone AU adopts the compact body. It uses the existing continuous millisecond width, minimum 48pt height, actual Dynamic Type text measurements, original wave PDF, and a six-point tail overlapping the body by one point. The wave PDF is 18×22 including stroke around the Figma 16×20 nominal box. Body width excludes the five-point tail extension. Unknown/nonpositive duration displays `-:--`; historical >60 seconds retains its real displayed duration. Mixed text, quote, multiple AU, deleted/draft/uploading content retains the original renderer and entity actions.

Body and VoiceOver actions call the existing owned AU consumer. Selection and long press keep priority. State and progress come from the existing player; no new network, playback engine, timer, permission or unread marker. A retained hidden RichText representation preserves the original entity consumer and mixed-content fallback. The old 24pt attachment hit test is retained for that representation; it does not describe the new standalone body target.

## Prepared native evidence

Existing App-hosted VoiceLayoutTests contains 17 original methods plus three new methods; all original method/helper text is unchanged after LF normalization. No target, selector, dependency or workflow changes. Expected cumulative count is **330 native + 3 navigation**, not an executed result.

- `testCompactVoiceOriginalRendererKeepsContinuousBodyAndReadableAXGeometry`: actual MessageCell/MessageViewLayout and Drafty, 320pt, light/dark, both directions, large/AXXXL, nil/nonpositive/1.5/4/30/60/61/extreme durations. Independent formula, actual label bounds, minimum height and original icon/tail geometry. Eight layout PNGs and matching geometry are prepared.
- `testCompactVoiceBodyActionsKeepSelectionLongPressAndMixedFallbackPriority`: actual cell handler with controlled gesture inputs, real bulk-selection consumer, VoiceOver action and reuse; mixed/quoted/multiple/uploading/draft/deleted fallback. This is not injected touchscreen recognition.
- `testCompactVoiceActualOwnedAVStateAndPositionReachVisibleControl`: existing real SQLite/SDK owner fixture, actual AVAudioPlayer/AAC and page AU consumer; visible playing/paused, actual fractional position/seek, inactive retirement and unchanged size. Two actual-state PNGs/geometry are prepared. Scope is synthetic local data, not an authenticated chat journey, server receipt, real microphone or cross-device acceptance.

Preparing/failure visuals are connected to the existing enum and recovery consumer but are not newly claimed as screenshot-verified. Original reliable-player tests remain. RESOURCE-CLEANUP-INHERITED and historical codec limitations remain; this visual change does not close them.

## Checks and recovery

`VOICE-UI-STATIC.json`: 44/44 Windows source policies. `VOICE-UI-CHECKS.json`: original 17 methods/helpers, seven-source boundary, exact PDF hashes, and diff check. Swift/UIKit/AV and new PNGs: **NOT_RUN**. CI46 remains 325 pass / 2 fail at `aaeab1b1`; its two red successor fixes require actual Mac confirmation.

Integration order: keep integration `c0e4a43b`, cherry-pick visual `89ccf1b`, then the independent test/docs successor. Do not cherry-pick the child duplicates of 13b/c0e again. Compare the integrated production/test tree with the reviewed child candidate before any authorized non-force push. Rollback only this unit by reverting the test successor and visual commit in reverse order; do not reset the worktree or remove untracked evidence. Original PDFs and all CI44–46 failures remain preserved.
