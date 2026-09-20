# QUALITY01 checkpoint — dependency blocked

Production is fixed at **`1aea86fb87f42a7d2d6215635c7c744262c8943e`**. The reviewed, not-yet-executed test candidate is **`0877d9a8411b0835a1076b426a92da64e0ab9468`**. The only non-documentation difference between them is `TinodiosUITests/ImageMessageLayoutTests.swift` and `TinodiosUITests/VoiceLayoutTests.swift`; current versions match candidate 0877 exactly. No dependency, protocol, storage, production player, selector or workflow change accompanies this checkpoint.

Pre-seal main worktree: `C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/work/r3-20260918-ios`, branch `codex/r3-20260918-ios`, documentation HEAD `b940db445f0d34e6ba8b0c29edefb309fa32d036`, tracked dirty 0 / untracked files 23538. The new files include preserved CI evidence; nothing was cleaned or replaced. Origin is `https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios.git`. The last authorized non-force push set `codex/verify-r2-ios02-20260918` to 0877; subsequent documentation commits have not been pushed. This handoff itself is a later documentation-only commit, whose exact SHA is reported separately.

Old child worktrees remain intact:

| Worktree / branch | HEAD | Tracked dirty / untracked |
| --- | --- | --- |
| `work/r4-quality01-ios-image` / `codex/r4-quality01-ios-image` | `86c775318eb9d8819e08c4c52377140de4be1489` | 0 / 2 |
| `work/r4-quality01-ios-voice` / `codex/r4-quality01-ios-voice` | `f208ca58f8fac644d40cfb4c3c3666e4053226d5` | 0 / 0 |

`evidence/CI51-final-worktrees.json` records these actual snapshots and the two-path source check. Neither child was merged, reset or updated for this checkpoint.

## Actual evidence

- **CI50:** exact production candidate 1aea compiled successfully; SDK44 + storage286 passed and storage6 failed, total **330 PASS / 6 FAIL**. Image6 was 1 PASS / 5 FAIL; AAC completion remained a real failure. Bare and production getter-free delegate-entry counts were both zero. Navigation/package/cold launch did not run. Original ZIP, traces and native attachment index are retained; see `CI50-RESULT.md`.
- **Successors:** `45bc5cdab4da2e28b8486ac2aecff0dbf12cf018` corrects two Image geometry test expectations; `dfb7bc04be8491bad9b461132b003a3995c220fc` adds bounded wait-stage evidence; `0877d9a8411b0835a1076b426a92da64e0ab9468` adds one independent real PCM control. All three have fixed-source review and Windows checks, **Mac NOT_RUN**. Expected next selection is **337 native + 3 navigation**.
- **CI51:** run `35497878843`, job `106044188211`, attempt 1, exact 0877. Static44 passed; CocoaPods failed to connect to the locked official MobileVLCKit archive before any native method ran. Original ZIP is 5065 bytes, SHA-256 `cf9c4c4b9e3bdc090da06aa9aaa086e97373c49ee2910ef33b9598082e1db475`. Its two entities, decoded original job log and source URL are recorded in `CI51-RESULT.md` / `evidence/CI51-result.json`. There is no new successful native or screenshot result.

The workflow has no explicit dependency archive cache restore/save, and this Windows tree has no Pods/CocoaPods cache at the bounded checked locations. The existing spec checksum is not an archive digest. Root reports that backend's single later official connection check also timed out with no HTTP response; it supplies no positive recovery evidence. This agent did not repeat that network check. No fallback URL, TLS relaxation, Pod upgrade or framework substitution was introduced. Current disposition is **specific external dependency connection blockage**, not a source failure or completed media acceptance.

## Review and recovery

Review the three independent commits with `git show <SHA>` in chronological order: 45bc, dfb, 0877. Their scope and exact inverse/assertion checks are in `evidence/CI50-image-geometry-fixture-checks.json`, `CI50-image-stage-diagnostic-checks.json` and `CI50-pcm-control-checks.json`. The older Image, compact voice, recording limit, continuous width and B02 source history is preserved.

After new trustworthy evidence that the exact locked official resource can be obtained, root may authorize **one** new same-source run. Do not silently change the candidate or repeat while the condition is unchanged. From the root workspace, the existing dispatch command verifies the remote branch SHA before dispatching:

```powershell
rtk python -X utf8 ops/integration/ios_ci_dispatch.py --dispatch --sha 0877d9a8411b0835a1076b426a92da64e0ab9468 --report work/r3-20260918-ios/docs/handoff/R4/QUALITY01/evidence/RECOVERY-dispatch.json
```

Use a fresh report name and record the resulting run/job/attempt, original artifact digest, exact methods and diagnostics. This is an instruction for an authorized later recovery, **not a dispatch performed here**. Preserve original 3-second waits and all current assertions. A successful dependency connection alone does not close the Image or AAC findings.

To inspect or recover source without disturbing these trees, create a new review worktree at the exact existing candidate commit rather than replacing the canonical checkout. If the three test successors must be withdrawn, review/revert 0877, then dfb, then 45bc in a separate branch, preserving the original commits and failure evidence. Do not reset or clean the current worktree and do not revert production 1aea as part of that test-only rollback. No rollback was executed.
