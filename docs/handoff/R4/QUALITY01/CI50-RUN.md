# CI50 — exact compilation successor

The reviewed source is `1aea86fb87f42a7d2d6215635c7c744262c8943e`. Root and backend approved the two explicit `CGFloat.greatestFiniteMagnitude` initializers after checking that their inverse reproduces the CI49 MessageCell source and that all other code and tests remain unchanged. CI49's line 212 diagnostic remains pending real compilation; source review alone does not close it.

On 2026-09-20 at 08:10 +08:00 the existing user-owned verification branch `codex/verify-r2-ios02-20260918` advanced without force from `8c3c7515ab49a98fa46c0b6bebf03665ee97a976` to that exact source. The local documentation HEAD `679a7293ff08fc7780d529facd93f0665fceab4f` was not pushed. One unsigned workflow dispatch returned HTTP 204. Run `35478057066`, job `105990668493`, attempt 1 was created at `2026-09-20T00:10:15Z`.

Initial status is **in progress**, not a passed result. Expected selection remains 336 native methods plus 3 navigation methods; the existing 45-minute job limit, assertions, dependencies and workflow are unchanged. The original CI49 ZIP and compilation failure remain preserved. This run must separately establish compilation, Image methods and getter-free AAC callback evidence before any related claim is updated.

Provenance: `evidence/CI50-dispatch.json` and `evidence/CI50-status-01.json`. Later actual results will be recorded separately; this note preserves the initial dispatch state.
