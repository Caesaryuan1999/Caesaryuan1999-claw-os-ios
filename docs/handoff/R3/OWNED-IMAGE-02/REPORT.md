# OWNED-IMAGE-02

Base: 7bacc0dd7f0dfc3660b12c624cfcae4665ff9a7f. Five production files; no SDK, schema, C3, AUTH, payload, or image-preview changes. File SHA-256 and exact new method list are in manifest.json.

## Fixed paths
- ClawSecondaryUIState: explicit captured owner + retained Store UID + injected current slot/generation. Reuses ClawMediaFiles URL/origin/cache rules and ClawMediaSession. Shared loader has no implicit Cache lookup. Every request gets an isolated ephemeral Kingfisher downloader; all redirects are rejected. Same-origin requests use captured owner's headers; legal external HTTPS requests strip Tinode/Authorization/Cookie headers. Cache key hashes service origin + UID + complete media URL and ignores inherited unscoped keys.
- Utils: nil URL rejects without force unwrap or network. Actual shared bridge settles PromisedReply outside SDK/Cache locks; its production factory binds the same captured Cache slot.
- RoundImageView: reuse, default icon, initials, branding and set(pub:) invalidate/cancel prior work. Completion revalidates captured scope and view generation before writing the image.
- AsyncImageTextAttachment: captures context at construction, invalidates on URL replacement, gates postprocessing/image/redraw together on main; failure log is fixed text. Existing nil postprocessing fallback to errorImage is retained.
- ThumbnailTransformer: captures context at construction; downloaded Drafty thumbnail mutation runs within that captured scope. No new server field or message send behavior.

## Validation
Windows: all 42 standalone source policies PASS; git diff --check PASS. Initial 41-script evidence preserved. These are source checks, not Swift execution.
10 new native methods compile actual Utils bridge, shared context/loader, RoundImageView, AsyncImageTextAttachment and unchanged EntityTextAttachment into the existing native target. They use real Tinode + SqlStore/BaseDb fixtures, real URLRequest modifier, actual Kingfisher memory cache, controlled transport completions, actual avatar and attachment mutations/layout invalidation. The only unrelated rendering adapters are UiUtils.letterTileColor and UIImage.noir; deleted rendering is not asserted.
Cases: same-origin/external headers + redirect decision + isolated downloader; nil URL; retained offline owner versus UID/slot/generation/logout; same-account cache hit/other-account miss; avatar A callback after B; default/brand resets; attachment success/postprocessing/redraw; logout suppression; URL replacement; actual Promise expiry.
The real current-Cache lookup is replaced only at the explicit injected slot boundary in native fixtures; production factory wiring is source-checked. Full ThumbnailTransformer/Drafty rendering is App compilation plus wiring inspection, not a native end-to-end rendering test. Actual URLSession redirect/network/provider/real-device behavior is NOT_RUN.
Expected cumulative native methods: SDK30 + storage132 = 162 (152 already passed on baseline CI9 plus 10 new). This delta has NOT_RUN on Mac.

## Existing CI9 facts and limits
Exact base CI9 run35287660307/job105423474366 passed SDK30 + storage122 = 152, including LocalMigration54 (original 12-round/24 concurrent initialization checks and four gate methods), Secondary13. The application-layer initialization gate passed this run; the Apple VFS internal cause remains unproven.
Unsigned simulator app zip SHA-256: 57b17ba973b6f244f6f4bdb26f5dbf67cc2f3f6722b648d835282bbbe302be14, build1736. Smoke stopped in the first simulator preflight; no install/launch occurred and no actual simulator state was recorded. This is not evidence of an App crash.

## Scope
No claim of a complete app-wide image/privacy audit. No global image cache deletion, no framework replacement, no change to other image libraries. Same-account offline eligibility does not require WebSocket authentication. Generation gates only reject stale callbacks; cache identity remains stable across same-account sessions.
