# CI49 exact integration

Integration before: `codex/r3-20260918-ios` at `5adb0673a79410eaa2204871a3627c6f4efd5be4`, tracked clean, origin the existing user-owned iOS repository. Image child: `codex/r4-quality01-ios-image` at `86c775318eb9d8819e08c4c52377140de4be1489`, tracked clean. Original untracked material is preserved.

Following root and independent reviews (`9420676d` Image tests; `51cac8ab` Observer), only the four approved image commits were cherry-picked, without merging the child:

| Child | Integration |
| --- | --- |
| 5c973463 | 9bd08e2 |
| 93ea7ee7 | 643eb80 |
| 446bc538 | 10b35ea |
| 86c77531 | 8c3c751 |

Exact candidate: **`8c3c7515ab49a98fa46c0b6bebf03665ee97a976`**. Seven production paths and three test/wiring paths match the child in Git mode/blob. The VoiceLayout test blob exactly preserves integration `5adb067`; every other non-docs entry remains equal to that integration base. Existing 330 methods + 3 navigation tests are retained, with six Image v1 methods added: **336 + 3 expected, not a passed count**. Windows source policies 44/44 and Git diff checks passed; new Swift execution is pending.

`evidence/CI49-image-integration.patch` is the original Git binary patch for those ten source paths, from `5adb067` to the exact candidate: 65919 bytes, SHA-256 `d730fd1018cf2a9b56975f9e26b46761ab1eb86f7d4c917dfe7d227d9b0a0146`. Exact mode/blob inventory is in `evidence/CI49-integration.json`. It is a source delta, not a substitute for the prior baseline. Apply only on a separate checkout of the exact base after `git apply --check`; retain the original checkout/index and original CI artifacts.

Remote verification branch was confirmed at `00425c0` before the authorized non-force push to the candidate. One unsigned Mac dispatch at 2026-09-20 07:47:49 +08 returned HTTP 204 (`evidence/CI49-dispatch.json`). No main, release, signing, dependency, timeout or workflow changes. No second dispatch. CI source remains the exact candidate even when this documentation is committed later. CI48 stays failed (329/1); its two real AAC controls both timed out, and the Observer successor is evidence instrumentation, not an accepted playback fix.

Registered run `35477080415`, job `105988063949`, attempt 1, created 2026-09-19 23:47:52 UTC. At the 07:48 +08 read the job was preparing Xcode/simulator; native execution, package and cold launch were still pending. Subsequent results belong in a separate acceptance/failure report and must not be inferred from this integration check.
