# Image v1 — iOS bounded read-only proposal

Source inspected: `db514ff4284aed249b4a073425c8379cce4d1943`. CI47 is testing this immutable voice candidate; this proposal changes no production, tests or shared design files. Basis: root DESIGN_SPEC Image v1 and QUALITY01_IMAGE_V1_HANDOFF (377:1849; light 383:1881; dark 383:1905). Design contexts must be read before later implementation; this source-mapping step does not claim a new Figma read or runtime screenshot.

## Actual path and differences

- FullFormatter.swift:74–89 reads IM `val/ref/width/height` and passes the entity key. VD independently reads `preview/preref` at92–111. QuoteFormatter:89–103 builds its own small image/video thumbnails; it must remain outside the new full-message policy.
- FormatNode.swift:405–448 already creates AsyncImageTextAttachment for an eligible remote IM reference and starts the owned download, including missing dimensions. This is **not** the Android missing-download defect. Current reliable dimensions or decoded inline pixels determine a proportional box; missing both falls back to a square. There is no long-image top crop or long-image label.
- AsyncImageTextAttachment.swift:49–72 validates captured context, attempt slot and URL, then replaces `image` and invalidates display. Bounds remain fixed. Merely keeping bounds does not guarantee FIT: a downloaded image must be composited proportionally into the fixed canvas, otherwise NSTextAttachment drawing can stretch it.
- RichTextView.swift:50–103 maps the actual attachment/key to `/image/preview`; MessageViewController+MessageCellDelegate.swift:794–813 passes original bytes/ref into the existing full-image route. ImagePreviewController:227–274 already uses captured owner, account cache key, no redirect and an independent downloader. Its existing failure retry is a full-preview action, not a new inline retry already implemented.
- MessageViewController:1560–1571 computes actual remaining width once; FormatNode receives that budget. The image unit must not add another 0.76 multiplier, alter audio widths, or change the global text formatter budget.

## Proposed exact seven production paths

| Repository-relative path | Narrow responsibility |
|---|---|
| `Tinodios/format/FullFormatter.swift` | Explicit full-IM presentation opt-in; preserve input fields/entity key and independent VD path. Quote/preview formatters keep their legacy default. |
| `Tinodios/format/FormatNode.swift` | Decide geometry from valid positive dimensions, then truly decoded inline pixels, otherwise unknown. Create fixed local canvas: long TOP 3:4/max240×320; unknown 3:2/max240×160 with FIT after success. Ordinary known ratio unchanged. Original data and metadata never rewritten. Compose real long-image/loading/failure presentation within that geometry. |
| `Tinodios/format/EntityTextAttachment.swift` | Small optional UI-only image presentation/binding metadata shared by sync/async attachments (default nil for other consumers). Keep original entity type/key. No network or dependency on FullFormatter/FormatNode, so the existing UIrunner target remains linkable. |
| `Tinodios/format/AsyncImageTextAttachment.swift` | Preserve captured owner/URL/slot and existing loader; apply the fixed-canvas postprocess consistently to success/failure. Expose actual loading/ready/failed state and bounded explicit retry of the same captured request; no current-Cache credential acquisition and no bounds change on completion. |
| `Tinodios/widgets/RichTextView.swift` | Actual failed opt-in image hit maps to a distinct local retry action carrying the original entity key; ready image remains original preview. Mixed content and quotes preserve their own glyph routes. |
| `Tinodios/MessageViewController+MessageCellDelegate.swift` | Retry consumer revalidates current page/message/IM/key and the currently displayed attachment, then invokes that attachment's same-scope retry. Never creates or publishes a message; normal full-image preview remains unchanged. |
| `Tinodios/MessageCell.swift` | Bind/unbind image presentation to the real cell; ensure late state updates cannot affect a reused cell. Provide accurate long-image/recovery accessibility semantics and layout-aware state presentation, preserving bulk selection, upload cancellation and long-press priority. No new image loading owner. |

No ImagePreviewController, uploader, ClawOwnedImageLoader, SDK, DB, wire, Pod, recording, video playback or voice-control modification is proposed. The exact UIKit state presentation must reuse the image attachment's fixed geometry; it must not add a second independent image download or a model-only state machine.

## Geometry and retained behavior

For reliable H/W≥3, body width is min(240, actual supplied positive width budget); height=width×4/3. Draw from the top of the orientation-correct source with aspect-fill into this rectangle, not a centered crop. Label “长图”; original full-image click remains reachable. Ordinary known images retain current proportional sizing. Unknown means neither reliable positive width/height nor a successfully decoded inline preview, not merely absent metadata.

Unknown width=min(240, actual width budget), height=width×2/3. Freeze this per attachment binding before the request. On success draw the entire orientation-correct source using min(width/sourceWidth,height/sourceHeight), centered with theme-appropriate blank margins. Do not assign downloaded pixels as an unprocessed image into a mismatched rectangle. Failure/loading content uses the same box; no timer-driven fake success. A fresh valid message/entity binding may compute a new box; completion of the old binding may not.

A declared dimension is a layout input, not proof of decoded content. Invalid/overflow/nonfinite values and corrupt bits must be handled without NaN geometry. Source pixels/ref/auth/query remain untouched. Do not fetch VD's video body to invent a poster. Uploading `mid:` and quoted/mixed messages retain their existing action semantics; new failed retry is only for a real eligible attachment owned by the current captured session.

## Meaningful verification and dependencies

- Existing `TinodiosUITests/OwnedImageTests.swift` has real production loader/Async attachment coverage but no full App import. Add only transport/state tests there if useful; keep its old cases and fixture ownership.
- Add `TinodiosUITests/ImageMessageLayoutTests.swift` to existing App-hosted `TinodiosVoiceLayoutTests`, with necessary `Tinodios.xcodeproj/project.pbxproj` membership and one class selector in `Scripts/ci/verify_publish_outcomes_macos.sh`. No new target/Pod/workflow. These three wiring paths require later task-pack approval.
- Real Drafty→FullFormatter→attachment→MessageCell/MessageViewLayout: 320pt, both directions, light/dark and AX; normal landscape/portrait/small images, H/W below/equal/above3; image with different top/middle/bottom pixel bands proves TOP, not center crop. Unknown initial geometry→real loopback success verifies FIT margins and stable bounds/content offset.
- Controlled actual failure/403/retry preserves original bytes/ref and message count; stale completion after cell reuse/owner retirement is ignored. Use existing real owner/SQLite and URLSession fixture seams; no new credentials or production login bypass. Actual original PNG/geometry and request counters must distinguish component rendering from authenticated chat/real-device acceptance.
- Preserve current 330 native + 3 navigation selectors and existing assertions; new method count only after implementation. Native APIs/runtime and all Image v1 screenshots are currently NOT_RUN.

This is a proposal for root freeze, not permission to edit these seven files yet. CI47 outcome and the two CI46 red-fix results remain independent. Inline retry and its accessibility state are proposed work, not already verified capability.
